import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/exchange_rate.dart';
import '../core/value_objects/money.dart';
import '../core/value_objects/scaled_math.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'post_purchase_command.dart';

class PostPurchaseService {
  PostPurchaseService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<PostPurchaseResult> execute(PostPurchaseCommand command) async {
    if (command.lines.isEmpty) {
      throw const DomainError('PURCHASE_LINES_REQUIRED', 'Purchase requires at least one line.');
    }
    if (command.exchangeRateScaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Exchange rate must be positive.');
    }
    if (command.settlementMode == PurchaseSettlementMode.credit &&
        (command.supplierId == null || command.supplierId!.trim().isEmpty)) {
      throw const DomainError('PURCHASE_CREDIT_SUPPLIER_REQUIRED', 'Credit purchase requires a supplier.');
    }

    final currency = _currency(command.currencyCode, 'MONEY_CURRENCY_INVALID');
    final baseCurrency = _currency(command.baseCurrencyCode, 'BASE_CURRENCY_INVALID');
    if (currency == baseCurrency && command.exchangeRateScaled != 100000000) {
      throw const DomainError('FX_BASE_RATE_INVALID', 'Base-currency purchase must use an exchange rate of 1.');
    }

    return db.transaction(() async {
      final existingOperation = await (db.select(db.operationLog)
            ..where((t) => t.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (existingOperation != null) {
        final purchase = await (db.select(db.purchases)
              ..where((t) => t.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (purchase == null) {
          throw const DomainError('OPERATION_STATE_CORRUPT', 'Operation exists without purchase truth.');
        }
        final payment = await (db.select(db.purchasePayments)
              ..where((t) => t.operationId.equals(command.operationId)))
            .getSingleOrNull();
        return PostPurchaseResult(
          purchaseId: purchase.id,
          documentNo: purchase.documentNo,
          journalEntryId: purchase.journalEntryId,
          stockMovementId: purchase.stockMovementId,
          paymentId: payment?.id,
          idempotentReplay: true,
        );
      }

      final rate = ExchangeRate.fromScaled(
        scaled: command.exchangeRateScaled,
        fromCurrency: currency,
        toCurrency: baseCurrency,
      );
      final snapshots = <_PurchaseLine>[];
      var totalScaled = 0;
      var baseTotalScaled = 0;
      for (final line in command.lines) {
        if (line.productId.trim().isEmpty || line.quantityScaled <= 0) {
          throw const DomainError('PURCHASE_QTY_INVALID', 'Purchase quantity must be positive.');
        }
        if (line.unitCostScaled < 0) {
          throw const DomainError('PURCHASE_COST_INVALID', 'Purchase unit cost cannot be negative.');
        }
        final net = divideHalfAwayFromZero(line.quantityScaled * line.unitCostScaled, 1000000);
        final baseNet = currency == baseCurrency
            ? net
            : rate.convert(Money.fromScaled(net, currency)).scaled;
        totalScaled = checkedInt64(totalScaled + net);
        baseTotalScaled = checkedInt64(baseTotalScaled + baseNet);
        snapshots.add(_PurchaseLine(input: line, netScaled: net, baseNetScaled: baseNet));
      }

      final purchaseId = _uuid.v4();
      final journalId = _uuid.v4();
      final movementId = _uuid.v4();
      final paymentId = command.settlementMode == PurchaseSettlementMode.cash ? _uuid.v4() : null;
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'purchase',
        year: command.purchaseAt.toUtc().year,
        prefix: 'PUR',
      );

      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              businessId: command.businessId,
              documentNo: documentNo,
              warehouseId: command.warehouseId,
              supplierId: Value(command.supplierId),
              settlementMode: Value(command.settlementMode.name),
              currencyCode: currency,
              baseCurrencyCode: baseCurrency,
              exchangeRateScaled: command.exchangeRateScaled,
              totalScaled: totalScaled,
              baseTotalScaled: baseTotalScaled,
              status: 'posted',
              purchaseAt: command.purchaseAt.toUtc(),
              journalEntryId: journalId,
              stockMovementId: movementId,
              operationId: command.operationId,
            ),
          );
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              id: movementId,
              businessId: command.businessId,
              warehouseId: command.warehouseId,
              movementType: 'PURCHASE_IN',
              referenceType: 'purchase',
              referenceId: purchaseId,
              status: 'posted',
              movementAt: command.purchaseAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      final qtyByProduct = <String, int>{};
      final valueByProduct = <String, int>{};
      for (final snapshot in snapshots) {
        await db.into(db.purchaseItems).insert(
              PurchaseItemsCompanion.insert(
                id: _uuid.v4(),
                purchaseId: purchaseId,
                productId: snapshot.input.productId,
                quantityScaled: snapshot.input.quantityScaled,
                unitCostScaled: snapshot.input.unitCostScaled,
                netScaled: snapshot.netScaled,
                baseNetScaled: snapshot.baseNetScaled,
              ),
            );
        final baseUnitCost = divideHalfAwayFromZero(
          snapshot.baseNetScaled * 1000000,
          snapshot.input.quantityScaled,
        );
        await db.into(db.stockMovementItems).insert(
              StockMovementItemsCompanion.insert(
                id: _uuid.v4(),
                stockMovementId: movementId,
                productId: snapshot.input.productId,
                quantityScaled: snapshot.input.quantityScaled,
                unitCostScaled: baseUnitCost,
                totalCostScaled: snapshot.baseNetScaled,
              ),
            );
        qtyByProduct.update(snapshot.input.productId, (v) => checkedInt64(v + snapshot.input.quantityScaled),
            ifAbsent: () => snapshot.input.quantityScaled);
        valueByProduct.update(snapshot.input.productId, (v) => checkedInt64(v + snapshot.baseNetScaled),
            ifAbsent: () => snapshot.baseNetScaled);
      }

      for (final productId in qtyByProduct.keys) {
        final old = await (db.select(db.inventoryBalances)
              ..where((t) => t.warehouseId.equals(command.warehouseId) & t.productId.equals(productId)))
            .getSingleOrNull();
        final newQty = checkedInt64((old?.quantityScaled ?? 0) + qtyByProduct[productId]!);
        final newValue = checkedInt64((old?.inventoryValueScaled ?? 0) + valueByProduct[productId]!);
        final newWac = divideHalfAwayFromZero(newValue * 1000000, newQty);
        if (old == null) {
          await db.into(db.inventoryBalances).insert(
                InventoryBalancesCompanion.insert(
                  warehouseId: command.warehouseId,
                  productId: productId,
                  quantityScaled: newQty,
                  inventoryValueScaled: newValue,
                  wacUnitCostScaled: newWac,
                  updatedAt: now,
                ),
              );
        } else {
          await (db.update(db.inventoryBalances)
                ..where((t) => t.warehouseId.equals(command.warehouseId) & t.productId.equals(productId)))
              .write(InventoryBalancesCompanion(
            quantityScaled: Value(newQty),
            inventoryValueScaled: Value(newValue),
            wacUnitCostScaled: Value(newWac),
            updatedAt: Value(now),
          ));
        }
      }

      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'purchase',
              sourceId: purchaseId,
              status: 'posted',
              entryAt: command.purchaseAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.inventoryLedgerAccountId,
              baseDebitScaled: Value(baseTotalScaled),
              description: const Value('Inventory purchase'),
            ),
          );
      final creditAccount = command.settlementMode == PurchaseSettlementMode.cash
          ? command.cashLedgerAccountId
          : command.accountsPayableLedgerAccountId;
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: creditAccount,
              baseCreditScaled: Value(baseTotalScaled),
              description: Value(command.settlementMode == PurchaseSettlementMode.cash
                  ? 'Cash purchase payment'
                  : 'Supplier payable'),
            ),
          );

      if (command.settlementMode == PurchaseSettlementMode.cash) {
        await db.into(db.purchasePayments).insert(
              PurchasePaymentsCompanion.insert(
                id: paymentId!,
                businessId: command.businessId,
                purchaseId: purchaseId,
                cashAccountId: command.cashAccountId,
                currencyCode: currency,
                amountScaled: totalScaled,
                baseAmountScaled: baseTotalScaled,
                paymentAt: command.purchaseAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      } else {
        await db.into(db.supplierLedger).insert(
              SupplierLedgerCompanion.insert(
                id: _uuid.v4(),
                businessId: command.businessId,
                supplierId: command.supplierId!,
                sourceType: 'purchase',
                sourceId: purchaseId,
                currencyCode: currency,
                creditScaled: Value(totalScaled),
                baseCreditScaled: Value(baseTotalScaled),
                occurredAt: command.purchaseAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      }

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'PostPurchase',
              entityType: const Value('purchase'),
              entityId: Value(purchaseId),
              status: 'committed',
              createdAt: now,
            ),
          );
      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'purchase',
              entityId: purchaseId,
              action: 'POST_PURCHASE',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'supplier_id': command.supplierId,
                'settlement_mode': command.settlementMode.name,
                'line_count': command.lines.length,
                'total_scaled': totalScaled,
                'base_total_scaled': baseTotalScaled,
                'currency': currency,
                'base_currency': baseCurrency,
              }),
            ),
          );

      return PostPurchaseResult(
        purchaseId: purchaseId,
        documentNo: documentNo,
        journalEntryId: journalId,
        stockMovementId: movementId,
        paymentId: paymentId,
        idempotentReplay: false,
      );
    });
  }

  String _currency(String value, String code) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw DomainError(code, 'Currency code must be 3 Latin letters.');
    }
    return normalized;
  }
}

class _PurchaseLine {
  const _PurchaseLine({required this.input, required this.netScaled, required this.baseNetScaled});
  final PostPurchaseLineInput input;
  final int netScaled;
  final int baseNetScaled;
}