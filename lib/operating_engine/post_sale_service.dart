import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/time/business_document_calendar.dart';
import '../core/value_objects/exchange_rate.dart';
import '../core/value_objects/money.dart';
import '../core/value_objects/scaled_math.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'post_sale_command.dart';

typedef SpikeFailureInjector = FutureOr<void> Function(String point);

class PostSaleService {
  PostSaleService(
    this.db, {
    Uuid? uuid,
    SpikeFailureInjector? failureInjector,
    BusinessDocumentCalendar calendar =
        FixedOffsetBusinessDocumentCalendar.utc,
  })  : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db),
        _calendar = calendar,
        _failureInjector = failureInjector;

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;
  final BusinessDocumentCalendar _calendar;
  final SpikeFailureInjector? _failureInjector;

  Future<PostSaleResult> execute(PostSaleCommand command) async {
    if (command.lines.isEmpty) {
      throw const DomainError('SALE_LINES_REQUIRED', 'Sale requires at least one line.');
    }
    if (command.exchangeRateScaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Exchange rate must be positive.');
    }
    if (command.settlementMode == SaleSettlementMode.credit &&
        (command.customerId == null || command.customerId!.trim().isEmpty)) {
      throw const DomainError(
        'SALE_CREDIT_CUSTOMER_REQUIRED',
        'Credit sale requires an explicit customer.',
      );
    }
    if (command.settlementMode == SaleSettlementMode.credit &&
        command.accountsReceivableLedgerAccountId.trim().isEmpty) {
      throw const DomainError(
        'SALE_AR_ACCOUNT_REQUIRED',
        'Credit sale requires an accounts receivable ledger account.',
      );
    }

    final currency = _normalizeCurrency(command.currencyCode, 'MONEY_CURRENCY_INVALID');
    final baseCurrency = _normalizeCurrency(command.baseCurrencyCode, 'BASE_CURRENCY_INVALID');

    return db.transaction(() async {
      final existingOperation = await (db.select(db.operationLog)
            ..where((t) => t.operationId.equals(command.operationId)))
          .getSingleOrNull();

      if (existingOperation != null) {
        final existingSale = await (db.select(db.sales)
              ..where((t) => t.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (existingSale == null) {
          throw const DomainError(
            'OPERATION_STATE_CORRUPT',
            'Operation exists without its canonical sale result.',
          );
        }
        final existingPayment = await (db.select(db.payments)
              ..where((t) => t.operationId.equals(command.operationId)))
            .getSingleOrNull();
        return PostSaleResult(
          saleId: existingSale.id,
          documentNo: existingSale.documentNo,
          journalEntryId: existingSale.journalEntryId,
          stockMovementId: existingSale.stockMovementId,
          paymentId: existingPayment?.id,
          idempotentReplay: true,
        );
      }

      final saleId = _uuid.v4();
      final journalId = _uuid.v4();
      final movementId = _uuid.v4();
      final paymentId = command.settlementMode == SaleSettlementMode.cash ? _uuid.v4() : null;
      final now = DateTime.now().toUtc();

      final rate = ExchangeRate.fromScaled(
        scaled: command.exchangeRateScaled,
        fromCurrency: currency,
        toCurrency: baseCurrency,
      );

      final requiredByProduct = <String, int>{};
      for (final line in command.lines) {
        if (line.quantityScaled <= 0) {
          throw const DomainError('SALE_QTY_INVALID', 'Sale quantity must be positive.');
        }
        if (line.unitPriceScaled < 0) {
          throw const DomainError('SALE_PRICE_INVALID', 'Sale price cannot be negative.');
        }
        requiredByProduct.update(
          line.productId,
          (current) => checkedInt64(current + line.quantityScaled),
          ifAbsent: () => checkedInt64(line.quantityScaled),
        );
      }

      final balancesByProduct = <String, InventoryBalance>{};
      for (final entry in requiredByProduct.entries) {
        final balance = await (db.select(db.inventoryBalances)
              ..where((t) =>
                  t.warehouseId.equals(command.warehouseId) &
                  t.productId.equals(entry.key)))
            .getSingleOrNull();
        if (balance == null || balance.quantityScaled < entry.value) {
          throw const DomainError('INV_INSUFFICIENT_STOCK', 'Insufficient stock for sale posting.');
        }
        balancesByProduct[entry.key] = balance;
      }

      var saleTotalScaled = 0;
      var cogsTotalScaled = 0;
      final lineSnapshots = <_LineSnapshot>[];
      for (final line in command.lines) {
        final balance = balancesByProduct[line.productId]!;
        final lineNet = divideHalfAwayFromZero(
          line.quantityScaled * line.unitPriceScaled,
          1000000,
        );
        final lineCogs = divideHalfAwayFromZero(
          line.quantityScaled * balance.wacUnitCostScaled,
          1000000,
        );
        saleTotalScaled = checkedInt64(saleTotalScaled + lineNet);
        cogsTotalScaled = checkedInt64(cogsTotalScaled + lineCogs);
        lineSnapshots.add(
          _LineSnapshot(
            input: line,
            netScaled: lineNet,
            cogsUnitCostScaled: balance.wacUnitCostScaled,
            cogsTotalScaled: lineCogs,
          ),
        );
      }

      final saleMoney = Money.fromScaled(saleTotalScaled, currency);
      final baseSaleMoney = currency == baseCurrency
          ? Money.fromScaled(saleTotalScaled, baseCurrency)
          : rate.convert(saleMoney);
      final baseCogsScaled = cogsTotalScaled;

      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'sale',
        year: _calendar.documentYear(command.saleAt),
        prefix: 'SAL',
      );
      await _failAt('after_sequence');

      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: saleId,
              businessId: command.businessId,
              documentNo: documentNo,
              warehouseId: command.warehouseId,
              customerId: Value(command.customerId),
              settlementMode: Value(command.settlementMode.name),
              currencyCode: currency,
              baseCurrencyCode: Value(baseCurrency),
              exchangeRateScaled: command.exchangeRateScaled,
              totalScaled: saleTotalScaled,
              baseTotalScaled: baseSaleMoney.scaled,
              status: 'posted',
              saleAt: command.saleAt.toUtc(),
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
              movementType: 'SALE_OUT',
              referenceType: 'sale',
              referenceId: saleId,
              status: 'posted',
              movementAt: command.saleAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      for (final snapshot in lineSnapshots) {
        await db.into(db.saleItems).insert(
              SaleItemsCompanion.insert(
                id: _uuid.v4(),
                saleId: saleId,
                productId: snapshot.input.productId,
                quantityScaled: snapshot.input.quantityScaled,
                baseQuantityScaled: snapshot.input.quantityScaled,
                unitPriceScaled: snapshot.input.unitPriceScaled,
                netScaled: snapshot.netScaled,
                cogsUnitCostScaled: snapshot.cogsUnitCostScaled,
                cogsTotalScaled: snapshot.cogsTotalScaled,
              ),
            );
        await db.into(db.stockMovementItems).insert(
              StockMovementItemsCompanion.insert(
                id: _uuid.v4(),
                stockMovementId: movementId,
                productId: snapshot.input.productId,
                quantityScaled: -snapshot.input.quantityScaled,
                unitCostScaled: snapshot.cogsUnitCostScaled,
                totalCostScaled: -snapshot.cogsTotalScaled,
              ),
            );
      }

      var inventoryWrites = 0;
      for (final entry in requiredByProduct.entries) {
        final balance = balancesByProduct[entry.key]!;
        final totalCogsForProduct = lineSnapshots
            .where((s) => s.input.productId == entry.key)
            .fold<int>(0, (sum, s) => checkedInt64(sum + s.cogsTotalScaled));
        final newQty = checkedInt64(balance.quantityScaled - entry.value);
        final newValue = checkedInt64(balance.inventoryValueScaled - totalCogsForProduct);
        await (db.update(db.inventoryBalances)
              ..where((t) =>
                  t.warehouseId.equals(command.warehouseId) &
                  t.productId.equals(entry.key)))
            .write(
          InventoryBalancesCompanion(
            quantityScaled: Value(newQty),
            inventoryValueScaled: Value(newValue),
            updatedAt: Value(now),
          ),
        );
        inventoryWrites++;
        if (inventoryWrites == 1) await _failAt('after_first_inventory_write');
      }

      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'sale',
              sourceId: saleId,
              status: 'posted',
              entryAt: command.saleAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      final settlementDebitAccount = command.settlementMode == SaleSettlementMode.cash
          ? command.cashLedgerAccountId
          : command.accountsReceivableLedgerAccountId;
      final settlementDescription = command.settlementMode == SaleSettlementMode.cash
          ? 'Cash sale receipt'
          : 'Customer receivable';
      final journalLines = [
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: settlementDebitAccount,
          baseDebitScaled: Value(baseSaleMoney.scaled),
          description: Value(settlementDescription),
        ),
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: command.salesRevenueAccountId,
          baseCreditScaled: Value(baseSaleMoney.scaled),
          description: const Value('Sales revenue'),
        ),
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: command.cogsLedgerAccountId,
          baseDebitScaled: Value(baseCogsScaled),
          description: const Value('Cost of goods sold'),
        ),
        JournalLinesCompanion.insert(
          id: _uuid.v4(),
          journalEntryId: journalId,
          accountId: command.inventoryLedgerAccountId,
          baseCreditScaled: Value(baseCogsScaled),
          description: const Value('Inventory relief'),
        ),
      ];
      for (final line in journalLines) {
        await db.into(db.journalLines).insert(line);
      }

      final debit = journalLines.fold<int>(0, (sum, line) {
        final value = line.baseDebitScaled.present ? line.baseDebitScaled.value : 0;
        return checkedInt64(sum + value);
      });
      final credit = journalLines.fold<int>(0, (sum, line) {
        final value = line.baseCreditScaled.present ? line.baseCreditScaled.value : 0;
        return checkedInt64(sum + value);
      });
      if (debit != credit) {
        throw const DomainError('ACC_ENTRY_UNBALANCED', 'Journal entry is not balanced.');
      }

      if (command.settlementMode == SaleSettlementMode.cash) {
        await db.into(db.payments).insert(
              PaymentsCompanion.insert(
                id: paymentId!,
                businessId: command.businessId,
                saleId: saleId,
                cashAccountId: command.cashAccountId,
                currencyCode: currency,
                amountScaled: saleTotalScaled,
                baseAmountScaled: baseSaleMoney.scaled,
                paymentAt: command.saleAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      } else {
        await db.into(db.customerLedger).insert(
              CustomerLedgerCompanion.insert(
                id: _uuid.v4(),
                businessId: command.businessId,
                customerId: command.customerId!,
                sourceType: 'sale',
                sourceId: saleId,
                currencyCode: currency,
                debitScaled: Value(saleTotalScaled),
                baseDebitScaled: Value(baseSaleMoney.scaled),
                occurredAt: command.saleAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      }

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'PostSale',
              entityType: const Value('sale'),
              entityId: Value(saleId),
              status: 'committed',
              createdAt: now,
            ),
          );

      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'sale',
              entityId: saleId,
              action: 'POST_SALE',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'line_count': command.lines.length,
                'total_scaled': saleTotalScaled,
                'currency': currency,
                'base_currency': baseCurrency,
                'settlement_mode': command.settlementMode.name,
                'customer_id': command.customerId,
              }),
            ),
          );

      await _failAt('before_commit');

      return PostSaleResult(
        saleId: saleId,
        documentNo: documentNo,
        journalEntryId: journalId,
        stockMovementId: movementId,
        paymentId: paymentId,
        idempotentReplay: false,
      );
    });
  }

  Future<void> _failAt(String point) async {
    final injector = _failureInjector;
    if (injector != null) await injector(point);
  }

  String _normalizeCurrency(String value, String code) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw DomainError(code, 'Currency code must be 3 Latin letters.');
    }
    return normalized;
  }
}

class _LineSnapshot {
  const _LineSnapshot({
    required this.input,
    required this.netScaled,
    required this.cogsUnitCostScaled,
    required this.cogsTotalScaled,
  });

  final PostSaleLineInput input;
  final int netScaled;
  final int cogsUnitCostScaled;
  final int cogsTotalScaled;
}
