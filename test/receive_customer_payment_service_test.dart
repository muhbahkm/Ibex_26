import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/receive_customer_payment_command.dart';
import 'package:ibex_foundation_spike/operating_engine/receive_customer_payment_service.dart';
import 'package:ibex_foundation_spike/queries/customer_balance_query.dart';

ReceiveCustomerPaymentCommand _command({String operationId = 'receipt-op-1'}) =>
    ReceiveCustomerPaymentCommand(
      operationId: operationId,
      businessId: 'B-1',
      userId: 'U-1',
      customerId: 'C-1',
      currencyCode: 'YER',
      baseCurrencyCode: 'YER',
      exchangeRateScaled: 100000000,
      amountScaled: 30 * 10000,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      accountsReceivableLedgerAccountId: 'ACC-AR',
      receivedAt: DateTime.utc(2026, 8, 11, 12),
    );

void main() {
  late SpikeDatabase db;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    await db.into(db.customerLedger).insert(
          CustomerLedgerCompanion.insert(
            id: 'LEDGER-SALE-1',
            businessId: 'B-1',
            customerId: 'C-1',
            sourceType: 'sale',
            sourceId: 'SALE-1',
            currencyCode: 'YER',
            debitScaled: const Value(80 * 10000),
            baseDebitScaled: const Value(80 * 10000),
            occurredAt: DateTime.utc(2026, 8, 11, 10),
            operationId: 'sale-op-1',
          ),
        );
  });

  tearDown(() => db.close());

  test('customer payment posts receipt journal ledger and reduces balance atomically', () async {
    final service = ReceiveCustomerPaymentService(db);
    final result = await service.execute(_command());

    expect(result.documentNo, 'RCT-2026-000001');
    expect(result.idempotentReplay, isFalse);
    expect(await db.select(db.customerReceipts).get(), hasLength(1));
    expect(await db.select(db.journalEntries).get(), hasLength(1));
    expect(await db.select(db.journalLines).get(), hasLength(2));
    expect(await db.select(db.operationLog).get(), hasLength(1));
    expect(await db.select(db.auditLogs).get(), hasLength(1));

    final lines = await db.select(db.journalLines).get();
    expect(lines.any((line) => line.accountId == 'ACC-CASH' && line.baseDebitScaled == 30 * 10000), isTrue);
    expect(lines.any((line) => line.accountId == 'ACC-AR' && line.baseCreditScaled == 30 * 10000), isTrue);

    final balances = await CustomerBalanceQuery(db).execute(
      businessId: 'B-1',
      customerId: 'C-1',
    );
    expect(balances.single.currencyCode, 'YER');
    expect(balances.single.balanceScaled, 50 * 10000);
  });

  test('same receipt operation id is idempotent', () async {
    final service = ReceiveCustomerPaymentService(db);
    final first = await service.execute(_command());
    final replay = await service.execute(_command());

    expect(replay.idempotentReplay, isTrue);
    expect(replay.receiptId, first.receiptId);
    expect(replay.documentNo, first.documentNo);
    expect(await db.select(db.customerReceipts).get(), hasLength(1));
    expect(await db.select(db.customerLedger).get(), hasLength(2));
  });
}
