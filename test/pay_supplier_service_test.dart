import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/pay_supplier_command.dart';
import 'package:ibex_foundation_spike/operating_engine/pay_supplier_service.dart';
import 'package:ibex_foundation_spike/queries/supplier_balance_query.dart';

void main() {
  late SpikeDatabase db;
  late PaySupplierService service;
  late SupplierBalanceQuery balances;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    service = PaySupplierService(db);
    balances = SupplierBalanceQuery(db);
    final now = DateTime.utc(2026, 8, 11);
    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            id: 'SUP-1',
            businessId: 'B-1',
            name: 'مورد العسل',
            normalizedName: 'مورد العسل',
            updatedAt: now,
          ),
        );
    await db.into(db.supplierLedger).insert(
          SupplierLedgerCompanion.insert(
            id: 'LED-PUR-1',
            businessId: 'B-1',
            supplierId: 'SUP-1',
            sourceType: 'purchase',
            sourceId: 'PUR-1',
            currencyCode: 'SAR',
            creditScaled: const Value(1000 * 10000),
            baseCreditScaled: const Value(1000 * 10000),
            occurredAt: now,
            operationId: 'OP-PUR-1',
          ),
        );
  });

  tearDown(() => db.close());

  PaySupplierCommand command() => PaySupplierCommand(
        operationId: 'OP-PAY-SUP-1',
        businessId: 'B-1',
        userId: 'U-1',
        supplierId: 'SUP-1',
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        amountScaled: 400 * 10000,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        accountsPayableLedgerAccountId: 'ACC-AP',
        paidAt: DateTime.utc(2026, 8, 11),
      );

  test('supplier payment posts document journal ledger and reduces payable balance atomically', () async {
    final result = await service.execute(command());
    expect(result.documentNo, 'PAY-2026-000001');
    expect(result.idempotentReplay, isFalse);

    final payment = await db.select(db.supplierPayments).getSingle();
    expect(payment.amountScaled, 400 * 10000);
    final journal = await db.select(db.journalLines).get();
    expect(journal.fold<int>(0, (s, l) => s + l.baseDebitScaled), 400 * 10000);
    expect(journal.fold<int>(0, (s, l) => s + l.baseCreditScaled), 400 * 10000);

    final ledger = await db.select(db.supplierLedger).get();
    expect(ledger, hasLength(2));
    final resultBalances = await balances.bySupplier(businessId: 'B-1', supplierId: 'SUP-1');
    expect(resultBalances.single.currencyCode, 'SAR');
    expect(resultBalances.single.balanceScaled, 600 * 10000);
    expect(await db.select(db.operationLog).get(), hasLength(1));
    expect(await db.select(db.auditLogs).get(), hasLength(1));
  });

  test('same PaySupplier operation is idempotent and does not duplicate truth', () async {
    final first = await service.execute(command());
    final second = await service.execute(command());
    expect(first.paymentId, second.paymentId);
    expect(second.idempotentReplay, isTrue);
    expect(await db.select(db.supplierPayments).get(), hasLength(1));
    expect(await db.select(db.journalEntries).get(), hasLength(1));
    expect(await db.select(db.supplierLedger).get(), hasLength(2));
  });

  test('unknown supplier is rejected before financial truth is written', () async {
    final invalid = PaySupplierCommand(
      operationId: 'OP-PAY-SUP-X',
      businessId: 'B-1',
      userId: 'U-1',
      supplierId: 'SUP-X',
      currencyCode: 'SAR',
      baseCurrencyCode: 'SAR',
      exchangeRateScaled: 100000000,
      amountScaled: 100 * 10000,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      accountsPayableLedgerAccountId: 'ACC-AP',
      paidAt: DateTime.utc(2026, 8, 11),
    );
    await expectLater(service.execute(invalid), throwsA(isA<Exception>()));
    expect(await db.select(db.supplierPayments).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });
}
