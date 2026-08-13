import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/exchange_rate.dart';
import '../core/value_objects/money.dart';
import '../core/value_objects/scaled_math.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'post_sale_return_command.dart';

class PostSaleReturnService {
  PostSaleReturnService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<PostSaleReturnResult> execute(PostSaleReturnCommand command) async {
    if (command.operationId.trim().isEmpty ||
        command.sourceSaleId.trim().isEmpty ||
        command.lines.isEmpty) {
      throw const DomainError('SALE_RETURN_INPUT_REQUIRED', 'Sale return operation, source sale and lines are required.');
    }

    final requestedBySourceItem = <String, int>{};
    for (final line in command.lines) {
      if (line.sourceSaleItemId.trim().isEmpty || line.quantityScaled <= 0) {
        throw const DomainError('SALE_RETURN_LINE_INVALID', 'Return lines require a source item and positive quantity.');
      }
      requestedBySourceItem.update(
        line.sourceSaleItemId,
        (value) => checkedInt64(value + line.quantityScaled),
        ifAbsent: () => checkedInt64(line.quantityScaled),
      );
    }

    return db.transaction(() async {
      final prior = await (db.select(db.operationLog)
            ..where((row) => row.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (prior != null) {
        final existing = await (db.select(db.saleReturns)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (existing == null) {
          throw const DomainError('OPERATION_STATE_CORRUPT', 'Operation exists without sale return truth.');
        }
        final refund = await (db.select(db.saleRefundPayments)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        return PostSaleReturnResult(
          saleReturnId: existing.id,
          documentNo: existing.documentNo,
          journalEntryId: existing.journalEntryId,
          stockMovementId: existing.stockMovementId,
          refundPaymentId: refund?.id,
          idempotentReplay: true,
        );
      }

      final sale = await (db.select(db.sales)
            ..where((row) =>
                row.id.equals(command.sourceSaleId) &
                row.businessId.equals(command.businessId)))
          .getSingleOrNull();
      if (sale == null || sale.status != 'posted') {
        throw const DomainError('SOURCE_SALE_NOT_POSTED', 'Return requires a posted source sale in this business.');
      }
      final baseCurrency = sale.baseCurrencyCode;
      if (baseCurrency == null || baseCurrency.trim().isEmpty) {
        throw const DomainError('SOURCE_SALE_BASE_CURRENCY_UNKNOWN', 'Cannot return a sale whose historical base currency is unproven.');
      }
      final isCredit = sale.settlementMode == 'credit';
      if (isCredit && (sale.customerId == null || sale.customerId!.trim().isEmpty)) {
        throw const DomainError('SOURCE_SALE_CUSTOMER_REQUIRED', 'Credit sale return requires the source customer.');
      }

      final sourceItems = <String, SaleItem>{};
      for (final entry in requestedBySourceItem.entries) {
        final source = await (db.select(db.saleItems)
              ..where((row) =>
                  row.id.equals(entry.key) & row.saleId.equals(sale.id)))
            .getSingleOrNull();
        if (source == null) {
          throw const DomainError('SOURCE_SALE_ITEM_NOT_FOUND', 'Return item is not part of the source sale.');
        }
        final alreadyReturned = await db.customSelect(
          '''
          SELECT COALESCE(SUM(sri.quantity_scaled), 0) AS returned_qty
          FROM sale_return_items sri
          INNER JOIN sale_returns sr ON sr.id = sri.sale_return_id
          WHERE sri.source_sale_item_id = ? AND sr.status = 'posted'
          ''',
          variables: [Variable.withString(source.id)],
          readsFrom: {db.saleReturns, db.saleReturnItems},
        ).getSingle();
        final returnedQty = alreadyReturned.read<int>('returned_qty');
        if (checkedInt64(returnedQty + entry.value) > source.quantityScaled) {
          throw const DomainError('SALE_RETURN_QTY_EXCEEDS_SOURCE', 'Cumulative return quantity exceeds the source sale item.');
        }
        sourceItems[source.id] = source;
      }

      final currency = sale.currencyCode.trim().toUpperCase();
      final normalizedBase = baseCurrency.trim().toUpperCase();
      final rate = ExchangeRate.fromScaled(
        scaled: sale.exchangeRateScaled,
        fromCurrency: currency,
        toCurrency: normalizedBase,
      );

      var totalScaled = 0;
      var cogsTotalScaled = 0;
      final snapshots = <_SaleReturnLineSnapshot>[];
      for (final line in command.lines) {
        final source = sourceItems[line.sourceSaleItemId]!;
        final refund = divideHalfAwayFromZero(
          line.quantityScaled * source.unitPriceScaled,
          1000000,
        );
        final cogs = divideHalfAwayFromZero(
          line.quantityScaled * source.cogsUnitCostScaled,
          1000000,
        );
        totalScaled = checkedInt64(totalScaled + refund);
        cogsTotalScaled = checkedInt64(cogsTotalScaled + cogs);
        snapshots.add(_SaleReturnLineSnapshot(
          input: line,
          source: source,
          refundScaled: refund,
          cogsTotalScaled: cogs,
        ));
      }
      final totalMoney = Money.fromScaled(totalScaled, currency);
      final baseTotal = currency == normalizedBase
          ? Money.fromScaled(totalScaled, normalizedBase)
          : rate.convert(totalMoney);

      final returnId = _uuid.v4();
      final journalId = _uuid.v4();
      final movementId = _uuid.v4();
      final refundPaymentId = isCredit ? null : _uuid.v4();
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'sales_return',
        year: command.returnedAt.toUtc().year,
        prefix: 'SRT',
      );

      await db.into(db.saleReturns).insert(
            SaleReturnsCompanion.insert(
              id: returnId,
              businessId: command.businessId,
              documentNo: documentNo,
              sourceSaleId: sale.id,
              warehouseId: sale.warehouseId,
              customerId: Value(sale.customerId),
              settlementMode: sale.settlementMode,
              currencyCode: currency,
              baseCurrencyCode: normalizedBase,
              exchangeRateScaled: sale.exchangeRateScaled,
              totalScaled: totalScaled,
              baseTotalScaled: baseTotal.scaled,
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
              warehouseId: sale.warehouseId,
              movementType: 'SALE_RETURN_IN',
              referenceType: 'sales_return',
              referenceId: returnId,
              status: 'posted',
              movementAt: command.returnedAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      final quantityByProduct = <String, int>{};
      final valueByProduct = <String, int>{};
      for (final snapshot in snapshots) {
        quantityByProduct.update(
          snapshot.source.productId,
          (value) => checkedInt64(value + snapshot.input.quantityScaled),
          ifAbsent: () => snapshot.input.quantityScaled,
        );
        valueByProduct.update(
          snapshot.source.productId,
          (value) => checkedInt64(value + snapshot.cogsTotalScaled),
          ifAbsent: () => snapshot.cogsTotalScaled,
        );
        await db.into(db.saleReturnItems).insert(
              SaleReturnItemsCompanion.insert(
                id: _uuid.v4(),
                saleReturnId: returnId,
                sourceSaleItemId: snapshot.source.id,
                productId: snapshot.source.productId,
                quantityScaled: snapshot.input.quantityScaled,
                unitPriceScaled: snapshot.source.unitPriceScaled,
                refundScaled: snapshot.refundScaled,
                cogsUnitCostScaled: snapshot.source.cogsUnitCostScaled,
                cogsTotalScaled: snapshot.cogsTotalScaled,
              ),
            );
        await db.into(db.stockMovementItems).insert(
              StockMovementItemsCompanion.insert(
                id: _uuid.v4(),
                stockMovementId: movementId,
                productId: snapshot.source.productId,
                quantityScaled: snapshot.input.quantityScaled,
                unitCostScaled: snapshot.source.cogsUnitCostScaled,
                totalCostScaled: snapshot.cogsTotalScaled,
              ),
            );
      }

      for (final entry in quantityByProduct.entries) {
        final productId = entry.key;
        final qty = entry.value;
        final value = valueByProduct[productId]!;
        final existing = await (db.select(db.inventoryBalances)
              ..where((row) =>
                  row.warehouseId.equals(sale.warehouseId) &
                  row.productId.equals(productId)))
            .getSingleOrNull();
        final newQty = checkedInt64((existing?.quantityScaled ?? 0) + qty);
        final newValue = checkedInt64((existing?.inventoryValueScaled ?? 0) + value);
        final newWac = divideHalfAwayFromZero(newValue * 1000000, newQty);
        if (existing == null) {
          await db.into(db.inventoryBalances).insert(
                InventoryBalancesCompanion.insert(
                  warehouseId: sale.warehouseId,
                  productId: productId,
                  quantityScaled: newQty,
                  inventoryValueScaled: newValue,
                  wacUnitCostScaled: newWac,
                  updatedAt: now,
                ),
              );
        } else {
          await (db.update(db.inventoryBalances)
                ..where((row) =>
                    row.warehouseId.equals(sale.warehouseId) &
                    row.productId.equals(productId)))
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
              sourceType: 'sales_return',
              sourceId: returnId,
              status: 'posted',
              entryAt: command.returnedAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      final settlementAccount = isCredit
          ? command.accountsReceivableLedgerAccountId
          : command.cashLedgerAccountId;
      final lines = [
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: command.salesRevenueAccountId,
          baseDebitScaled: Value(baseTotal.scaled),
          description: const Value('Sales return revenue reversal'),
        ),
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: settlementAccount,
          baseCreditScaled: Value(baseTotal.scaled),
          description: Value(isCredit ? 'Receivable reduction' : 'Cash refund'),
        ),
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: command.inventoryLedgerAccountId,
          baseDebitScaled: Value(cogsTotalScaled),
          description: const Value('Returned inventory restoration'),
        ),
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: command.cogsLedgerAccountId,
          baseCreditScaled: Value(cogsTotalScaled),
          description: const Value('COGS reversal'),
        ),
      ];
      for (final line in lines) {
        await db.into(db.journalLines).insert(line);
      }
      final debit = lines.fold<int>(0, (sum, line) => checkedInt64(sum + (line.baseDebitScaled.present ? line.baseDebitScaled.value : 0)));
      final credit = lines.fold<int>(0, (sum, line) => checkedInt64(sum + (line.baseCreditScaled.present ? line.baseCreditScaled.value : 0)));
      if (debit != credit) {
        throw const DomainError('ACC_ENTRY_UNBALANCED', 'Sale return journal entry is not balanced.');
      }

      if (isCredit) {
        await db.into(db.customerLedger).insert(
              CustomerLedgerCompanion.insert(
                id: _uuid.v4(),
                businessId: command.businessId,
                customerId: sale.customerId!,
                sourceType: 'sales_return',
                sourceId: returnId,
                currencyCode: currency,
                creditScaled: Value(totalScaled),
                baseCreditScaled: Value(baseTotal.scaled),
                occurredAt: command.returnedAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      } else {
        await db.into(db.saleRefundPayments).insert(
              SaleRefundPaymentsCompanion.insert(
                id: refundPaymentId!,
                businessId: command.businessId,
                saleReturnId: returnId,
                cashAccountId: command.cashAccountId,
                currencyCode: currency,
                amountScaled: totalScaled,
                baseAmountScaled: baseTotal.scaled,
                refundedAt: command.returnedAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      }

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'PostSaleReturn',
              entityType: const Value('sales_return'),
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
              entityType: 'sales_return',
              entityId: returnId,
              action: 'POST_SALE_RETURN',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'source_sale_id': sale.id,
                'total_scaled': totalScaled,
                'currency': currency,
                'base_total_scaled': baseTotal.scaled,
                'base_currency': normalizedBase,
                'settlement_mode': sale.settlementMode,
              }),
            ),
          );

      return PostSaleReturnResult(
        saleReturnId: returnId,
        documentNo: documentNo,
        journalEntryId: journalId,
        stockMovementId: movementId,
        refundPaymentId: refundPaymentId,
        idempotentReplay: false,
      );
    });
  }
}

class _SaleReturnLineSnapshot {
  const _SaleReturnLineSnapshot({
    required this.input,
    required this.source,
    required this.refundScaled,
    required this.cogsTotalScaled,
  });

  final PostSaleReturnLineInput input;
  final SaleItem source;
  final int refundScaled;
  final int cogsTotalScaled;
}
