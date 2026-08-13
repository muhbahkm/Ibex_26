import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/scaled_math.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'post_purchase_return_command.dart';

class PostPurchaseReturnService {
  PostPurchaseReturnService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<PostPurchaseReturnResult> execute(PostPurchaseReturnCommand command) async {
    if (command.operationId.trim().isEmpty || command.lines.isEmpty) {
      throw const DomainError('PURCHASE_RETURN_INPUT_REQUIRED', 'Purchase return operation and lines are required.');
    }
    for (final line in command.lines) {
      if (line.sourcePurchaseItemId.trim().isEmpty || line.quantityScaled <= 0) {
        throw const DomainError('PURCHASE_RETURN_LINE_INVALID', 'Purchase return lines require a source item and positive quantity.');
      }
    }

    return db.transaction(() async {
      final priorOperation = await (db.select(db.operationLog)
            ..where((r) => r.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (priorOperation != null) {
        final prior = await (db.select(db.purchaseReturns)
              ..where((r) => r.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (prior == null) {
          throw const DomainError('OPERATION_STATE_CORRUPT', 'Operation exists without purchase return truth.');
        }
        final cashReceipt = await (db.select(db.purchaseReturnCashReceipts)
              ..where((r) => r.operationId.equals(command.operationId)))
            .getSingleOrNull();
        return PostPurchaseReturnResult(
          purchaseReturnId: prior.id,
          documentNo: prior.documentNo,
          journalEntryId: prior.journalEntryId,
          stockMovementId: prior.stockMovementId,
          cashReceiptId: cashReceipt?.id,
          idempotentReplay: true,
        );
      }

      final purchase = await (db.select(db.purchases)
            ..where((r) =>
                r.id.equals(command.sourcePurchaseId) &
                r.businessId.equals(command.businessId) &
                r.status.equals('posted')))
          .getSingleOrNull();
      if (purchase == null) {
        throw const DomainError('SOURCE_PURCHASE_NOT_FOUND', 'Posted source purchase was not found in this business.');
      }

      final requestedByItem = <String, int>{};
      for (final line in command.lines) {
        requestedByItem.update(
          line.sourcePurchaseItemId,
          (v) => checkedInt64(v + line.quantityScaled),
          ifAbsent: () => line.quantityScaled,
        );
      }

      final sourceItems = <String, PurchaseItem>{};
      for (final entry in requestedByItem.entries) {
        final sourceItem = await (db.select(db.purchaseItems)
              ..where((r) =>
                  r.id.equals(entry.key) &
                  r.purchaseId.equals(purchase.id)))
            .getSingleOrNull();
        if (sourceItem == null) {
          throw const DomainError('PURCHASE_RETURN_SOURCE_ITEM_INVALID', 'Return item does not belong to the source purchase.');
        }
        final previousRows = await (db.select(db.purchaseReturnItems)
              ..where((r) => r.sourcePurchaseItemId.equals(sourceItem.id)))
            .get();
        final previouslyReturned = previousRows.fold<int>(0, (s, r) => checkedInt64(s + r.quantityScaled));
        if (checkedInt64(previouslyReturned + entry.value) > sourceItem.quantityScaled) {
          throw const DomainError('PURCHASE_RETURN_QTY_EXCEEDED', 'Cumulative return quantity exceeds source purchase quantity.');
        }
        sourceItems[entry.key] = sourceItem;
      }

      final qtyByProduct = <String, int>{};
      final baseValueByProduct = <String, int>{};
      var totalScaled = 0;
      var baseTotalScaled = 0;
      final snapshots = <_ReturnLine>[];
      for (final line in command.lines) {
        final source = sourceItems[line.sourcePurchaseItemId]!;
        final amount = divideHalfAwayFromZero(
          line.quantityScaled * source.unitCostScaled,
          1000000,
        );
        final baseAmount = divideHalfAwayFromZero(
          line.quantityScaled * source.baseNetScaled,
          source.quantityScaled,
        );
        totalScaled = checkedInt64(totalScaled + amount);
        baseTotalScaled = checkedInt64(baseTotalScaled + baseAmount);
        qtyByProduct.update(source.productId, (v) => checkedInt64(v + line.quantityScaled),
            ifAbsent: () => line.quantityScaled);
        baseValueByProduct.update(source.productId, (v) => checkedInt64(v + baseAmount),
            ifAbsent: () => baseAmount);
        snapshots.add(_ReturnLine(input: line, source: source, amountScaled: amount, baseAmountScaled: baseAmount));
      }

      final balances = <String, InventoryBalance>{};
      for (final entry in qtyByProduct.entries) {
        final balance = await (db.select(db.inventoryBalances)
              ..where((r) =>
                  r.warehouseId.equals(purchase.warehouseId) &
                  r.productId.equals(entry.key)))
            .getSingleOrNull();
        if (balance == null || balance.quantityScaled < entry.value) {
          throw const DomainError('INV_INSUFFICIENT_STOCK', 'Insufficient stock to return the purchased goods.');
        }
        final returnValue = baseValueByProduct[entry.key]!;
        if (balance.inventoryValueScaled < returnValue) {
          throw const DomainError('INV_RETURN_VALUE_INSUFFICIENT', 'Inventory carrying value is insufficient for source-cost purchase return.');
        }
        balances[entry.key] = balance;
      }

      final returnId = _uuid.v4();
      final journalId = _uuid.v4();
      final movementId = _uuid.v4();
      final cashReceiptId = purchase.settlementMode == 'cash' ? _uuid.v4() : null;
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'purchase_return',
        year: command.returnedAt.toUtc().year,
        prefix: 'PRT',
      );

      await db.into(db.purchaseReturns).insert(
            PurchaseReturnsCompanion.insert(
              id: returnId,
              businessId: command.businessId,
              documentNo: documentNo,
              sourcePurchaseId: purchase.id,
              warehouseId: purchase.warehouseId,
              supplierId: Value(purchase.supplierId),
              settlementMode: purchase.settlementMode,
              currencyCode: purchase.currencyCode,
              baseCurrencyCode: purchase.baseCurrencyCode,
              exchangeRateScaled: purchase.exchangeRateScaled,
              totalScaled: totalScaled,
              baseTotalScaled: baseTotalScaled,
              status: 'posted',
              returnedAt: command.returnedAt.toUtc(),
              journalEntryId: journalId,
              stockMovementId: movementId,
              operationId: command.operationId,
            ),
          );
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              id: movementId,
              businessId: command.businessId,
              warehouseId: purchase.warehouseId,
              movementType: 'PURCHASE_RETURN_OUT',
              referenceType: 'purchase_return',
              referenceId: returnId,
              status: 'posted',
              movementAt: command.returnedAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      for (final snapshot in snapshots) {
        final baseUnitCost = divideHalfAwayFromZero(
          snapshot.baseAmountScaled * 1000000,
          snapshot.input.quantityScaled,
        );
        await db.into(db.purchaseReturnItems).insert(
              PurchaseReturnItemsCompanion.insert(
                id: _uuid.v4(),
                purchaseReturnId: returnId,
                sourcePurchaseItemId: snapshot.source.id,
                productId: snapshot.source.productId,
                quantityScaled: snapshot.input.quantityScaled,
                unitCostScaled: snapshot.source.unitCostScaled,
                returnScaled: snapshot.amountScaled,
                baseReturnScaled: snapshot.baseAmountScaled,
              ),
            );
        await db.into(db.stockMovementItems).insert(
              StockMovementItemsCompanion.insert(
                id: _uuid.v4(),
                stockMovementId: movementId,
                productId: snapshot.source.productId,
                quantityScaled: -snapshot.input.quantityScaled,
                unitCostScaled: baseUnitCost,
                totalCostScaled: -snapshot.baseAmountScaled,
              ),
            );
      }

      for (final productId in qtyByProduct.keys) {
        final old = balances[productId]!;
        final newQty = checkedInt64(old.quantityScaled - qtyByProduct[productId]!);
        final newValue = checkedInt64(old.inventoryValueScaled - baseValueByProduct[productId]!);
        if (newQty == 0 && newValue != 0) {
          throw const DomainError('INV_ZERO_QTY_NONZERO_VALUE', 'Purchase return would leave zero quantity with non-zero carrying value.');
        }
        final newWac = newQty == 0
            ? 0
            : divideHalfAwayFromZero(newValue * 1000000, newQty);
        await (db.update(db.inventoryBalances)
              ..where((r) =>
                  r.warehouseId.equals(purchase.warehouseId) &
                  r.productId.equals(productId)))
            .write(
          InventoryBalancesCompanion(
            quantityScaled: Value(newQty),
            inventoryValueScaled: Value(newValue),
            wacUnitCostScaled: Value(newWac),
            updatedAt: Value(now),
          ),
        );
      }

      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'purchase_return',
              sourceId: returnId,
              status: 'posted',
              entryAt: command.returnedAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      final debitAccount = purchase.settlementMode == 'cash'
          ? command.cashLedgerAccountId
          : command.accountsPayableLedgerAccountId;
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: debitAccount,
              baseDebitScaled: Value(baseTotalScaled),
              description: Value(purchase.settlementMode == 'cash'
                  ? 'Purchase return cash receipt'
                  : 'Supplier payable reduction'),
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.inventoryLedgerAccountId,
              baseCreditScaled: Value(baseTotalScaled),
              description: const Value('Inventory purchase return'),
            ),
          );

      if (purchase.settlementMode == 'cash') {
        await db.into(db.purchaseReturnCashReceipts).insert(
              PurchaseReturnCashReceiptsCompanion.insert(
                id: cashReceiptId!,
                businessId: command.businessId,
                purchaseReturnId: returnId,
                cashAccountId: command.cashAccountId,
                currencyCode: purchase.currencyCode,
                amountScaled: totalScaled,
                baseAmountScaled: baseTotalScaled,
                receivedAt: command.returnedAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      } else {
        if (purchase.supplierId == null || purchase.supplierId!.trim().isEmpty) {
          throw const DomainError('PURCHASE_RETURN_SUPPLIER_REQUIRED', 'Credit source purchase has no supplier identity.');
        }
        await db.into(db.supplierLedger).insert(
              SupplierLedgerCompanion.insert(
                id: _uuid.v4(),
                businessId: command.businessId,
                supplierId: purchase.supplierId!,
                sourceType: 'purchase_return',
                sourceId: returnId,
                currencyCode: purchase.currencyCode,
                debitScaled: Value(totalScaled),
                baseDebitScaled: Value(baseTotalScaled),
                occurredAt: command.returnedAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      }

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'PostPurchaseReturn',
              entityType: const Value('purchase_return'),
              entityId: Value(returnId),
              status: 'committed',
              createdAt: now,
            ),
          );
      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'purchase_return',
              entityId: returnId,
              action: 'POST_PURCHASE_RETURN',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'source_purchase_id': purchase.id,
                'supplier_id': purchase.supplierId,
                'settlement_mode': purchase.settlementMode,
                'total_scaled': totalScaled,
                'base_total_scaled': baseTotalScaled,
                'currency': purchase.currencyCode,
                'base_currency': purchase.baseCurrencyCode,
              }),
            ),
          );

      return PostPurchaseReturnResult(
        purchaseReturnId: returnId,
        documentNo: documentNo,
        journalEntryId: journalId,
        stockMovementId: movementId,
        cashReceiptId: cashReceiptId,
        idempotentReplay: false,
      );
    });
  }
}

class _ReturnLine {
  const _ReturnLine({
    required this.input,
    required this.source,
    required this.amountScaled,
    required this.baseAmountScaled,
  });

  final PostPurchaseReturnLineInput input;
  final PurchaseItem source;
  final int amountScaled;
  final int baseAmountScaled;
}
