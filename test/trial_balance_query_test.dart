import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_service.dart';
import 'package:ibex_foundation_spike/operating_engine/reverse_expense_command.dart';
import 'package:ibex_foundation_spike/operating_engine/reverse_expense_service.dart';
import 'package:ibex_foundation_spike/queries/trial_balance_query.dart';

void main() {
  late SpikeDatabase db;
  final now = DateTime.utc(2026, 8, 11, 12);

  setUp(() {
    db = SpikeDatabase.inMemory();
  });

  tearDown(() => db.close());

  test('posted journal activity is business scoped and globally balanced', () async {
    final expenses = PostExpenseService(db);
    await expenses.execute(
      PostExpenseCommand(
        operationId: 'OP-EXP-B1',
        businessId: 'B-1',
        userId: 'U-1',
        category: 'نقل',
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        amountScaled: 125 * 10000,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        expenseLedgerAccountId: 'ACC-EXP',
        expenseAt: now,
      ),
    );
    await expenses.execute(
      PostExpenseCommand(
        operationId: 'OP-EXP-B2',
        businessId: 'B-2',
        userId: 'U-2',
        category: 'نقل',
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        amountScaled: 999 * 10000,
        cashAccountId: 'CASH-2',
        cashLedgerAccountId: 'ACC-CASH',
        expenseLedgerAccountId: 'ACC-EXP',
        expenseAt: now,
      ),
    );

    final report = await TrialBalanceQuery(db).load(
      businessId: 'B-1',
      fromInclusive: DateTime.utc(2026, 8, 11),
      toExclusive: DateTime.utc(2026, 8, 12),
    );

    expect(report.isBalanced, isTrue);
    expect(report.totalDebitScaled, 125 * 10000);
    expect(report.totalCreditScaled, 125 * 10000);
    expect(report.rows, hasLength(2));
    expect(
      report.rows.singleWhere((r) => r.accountId == 'ACC-EXP').debitScaled,
      125 * 10000,
    );
  });

  test('expense plus linked reversal nets each affected account to zero', () async {
    final expenses = PostExpenseService(db);
    final posted = await expenses.execute(
      PostExpenseCommand(
        operationId: 'OP-EXP-1',
        businessId: 'B-1',
        userId: 'U-1',
        category: 'نقل',
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        amountScaled: 125 * 10000,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        expenseLedgerAccountId: 'ACC-EXP',
        expenseAt: now,
      ),
    );
    await ReverseExpenseService(db).execute(
      ReverseExpenseCommand(
        operationId: 'OP-EXR-1',
        businessId: 'B-1',
        userId: 'U-1',
        sourceExpenseId: posted.expenseId,
        reason: 'تصحيح',
        reversedAt: now.add(const Duration(minutes: 1)),
      ),
    );

    final report = await TrialBalanceQuery(db).load(
      businessId: 'B-1',
      fromInclusive: DateTime.utc(2026, 8, 11),
      toExclusive: DateTime.utc(2026, 8, 12),
    );

    expect(report.isBalanced, isTrue);
    expect(report.totalDebitScaled, 250 * 10000);
    expect(report.totalCreditScaled, 250 * 10000);
    expect(report.rows.every((r) => r.netDebitScaled == 0), isTrue);
  });

  test('invalid date range fails before query execution', () async {
    await expectLater(
      TrialBalanceQuery(db).load(
        businessId: 'B-1',
        fromInclusive: DateTime.utc(2026, 8, 12),
        toExclusive: DateTime.utc(2026, 8, 11),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
