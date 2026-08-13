import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_service.dart';

void main() {
  late SpikeDatabase db;
  late PostExpenseService expenses;
  final now = DateTime.utc(2026, 8, 11);

  setUp(() {
    db = SpikeDatabase.inMemory();
    expenses = PostExpenseService(db);
  });

  tearDown(() => db.close());

  PostExpenseCommand command({
    String operationId = 'OP-EXP-1',
    String currency = 'SAR',
    String baseCurrency = 'SAR',
    int rate = 100000000,
    int amount = 125 * 10000,
  }) => PostExpenseCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        category: 'نقل',
        description: 'نقل طلبية',
        currencyCode: currency,
        baseCurrencyCode: baseCurrency,
        exchangeRateScaled: rate,
        amountScaled: amount,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        expenseLedgerAccountId: 'ACC-EXP-TRANSPORT',
        expenseAt: now,
      );

  test('posts immutable expense with balanced journal and audit evidence', () async {
    final result = await expenses.execute(command());
    expect(result.documentNo, 'EXP-2026-000001');
    expect(result.idempotentReplay, isFalse);

    final expense = await db.select(db.expenses).getSingle();
    expect(expense.category, 'نقل');
    expect(expense.amountScaled, 125 * 10000);
    expect(expense.baseAmountScaled, 125 * 10000);
    expect(expense.status, 'posted');

    final lines = await (db.select(db.journalLines)
          ..where((row) => row.journalEntryId.equals(result.journalEntryId)))
        .get();
    expect(lines, hasLength(2));
    expect(lines.fold<int>(0, (sum, row) => sum + row.baseDebitScaled), 125 * 10000);
    expect(lines.fold<int>(0, (sum, row) => sum + row.baseCreditScaled), 125 * 10000);
    expect(await db.select(db.operationLog).get(), hasLength(1));
    expect(await db.select(db.auditLogs).get(), hasLength(1));
  });

  test('multi-currency expense freezes converted base amount', () async {
    await expenses.execute(command(
      currency: 'USD',
      baseCurrency: 'SAR',
      rate: 375000000,
      amount: 100 * 10000,
    ));

    final expense = await db.select(db.expenses).getSingle();
    expect(expense.exchangeRateScaled, 375000000);
    expect(expense.baseAmountScaled, 375 * 10000);
  });

  test('same operation id is idempotent and does not duplicate truth', () async {
    final first = await expenses.execute(command());
    final second = await expenses.execute(command());
    expect(second.expenseId, first.expenseId);
    expect(second.idempotentReplay, isTrue);
    expect(await db.select(db.expenses).get(), hasLength(1));
    expect(await db.select(db.journalEntries).get(), hasLength(1));
    expect(await db.select(db.auditLogs).get(), hasLength(1));
  });

  test('base-currency expense rejects non-1e8 FX before mutation', () async {
    await expectLater(
      expenses.execute(command(rate: 200000000)),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.expenses).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('zero amount is rejected before document sequence allocation', () async {
    await expectLater(
      expenses.execute(command(amount: 0)),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.expenses).get(), isEmpty);
    final sequences = await db.customSelect(
      "SELECT * FROM document_sequences WHERE document_type = 'expense'",
    ).get();
    expect(sequences, isEmpty);
  });
}
