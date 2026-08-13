import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_service.dart';
import 'package:ibex_foundation_spike/operating_engine/reverse_expense_command.dart';
import 'package:ibex_foundation_spike/operating_engine/reverse_expense_service.dart';

void main() {
  late SpikeDatabase db;
  late PostExpenseService postExpense;
  late ReverseExpenseService reverseExpense;
  final now = DateTime.utc(2026, 8, 11);

  setUp(() {
    db = SpikeDatabase.inMemory();
    postExpense = PostExpenseService(db);
    reverseExpense = ReverseExpenseService(db);
  });

  tearDown(() => db.close());

  Future<String> postSource({String operationId = 'OP-EXP-SOURCE'}) async {
    final result = await postExpense.execute(
      PostExpenseCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        category: 'نقل',
        description: 'مصروف قابل للعكس',
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        amountScaled: 125 * 10000,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        expenseLedgerAccountId: 'ACC-EXP-TRANSPORT',
        expenseAt: now,
      ),
    );
    return result.expenseId;
  }

  ReverseExpenseCommand command({
    required String sourceExpenseId,
    String operationId = 'OP-EXR-1',
    String businessId = 'B-1',
    String reason = 'إدخال المصروف بالخطأ',
  }) => ReverseExpenseCommand(
        operationId: operationId,
        businessId: businessId,
        userId: 'U-1',
        sourceExpenseId: sourceExpenseId,
        reason: reason,
        reversedAt: now.add(const Duration(minutes: 5)),
      );

  test('reversal creates linked compensating journal and preserves source values', () async {
    final sourceId = await postSource();
    final before = await (db.select(db.expenses)..where((r) => r.id.equals(sourceId))).getSingle();

    final result = await reverseExpense.execute(command(sourceExpenseId: sourceId));

    expect(result.documentNo, 'EXR-2026-000001');
    expect(result.idempotentReplay, isFalse);
    final source = await (db.select(db.expenses)..where((r) => r.id.equals(sourceId))).getSingle();
    expect(source.status, 'reversed');
    expect(source.amountScaled, before.amountScaled);
    expect(source.baseAmountScaled, before.baseAmountScaled);
    expect(source.category, before.category);
    expect(source.exchangeRateScaled, before.exchangeRateScaled);

    final reversal = await db.select(db.expenseReversals).getSingle();
    expect(reversal.sourceExpenseId, sourceId);
    expect(reversal.reason, 'إدخال المصروف بالخطأ');

    final sourceLines = await (db.select(db.journalLines)
          ..where((r) => r.journalEntryId.equals(before.journalEntryId)))
        .get();
    final reversalLines = await (db.select(db.journalLines)
          ..where((r) => r.journalEntryId.equals(result.journalEntryId)))
        .get();
    expect(reversalLines, hasLength(sourceLines.length));
    expect(
      sourceLines.fold<int>(0, (s, r) => s + r.baseDebitScaled) +
          reversalLines.fold<int>(0, (s, r) => s + r.baseDebitScaled),
      sourceLines.fold<int>(0, (s, r) => s + r.baseCreditScaled) +
          reversalLines.fold<int>(0, (s, r) => s + r.baseCreditScaled),
    );
    for (final sourceLine in sourceLines) {
      final inverse = reversalLines.singleWhere((r) => r.accountId == sourceLine.accountId);
      expect(inverse.baseDebitScaled, sourceLine.baseCreditScaled);
      expect(inverse.baseCreditScaled, sourceLine.baseDebitScaled);
    }
    expect(await db.select(db.operationLog).get(), hasLength(2));
    expect(await db.select(db.auditLogs).get(), hasLength(2));
  });

  test('same reversal operation id is idempotent', () async {
    final sourceId = await postSource();
    final first = await reverseExpense.execute(command(sourceExpenseId: sourceId));
    final second = await reverseExpense.execute(command(sourceExpenseId: sourceId));

    expect(second.expenseReversalId, first.expenseReversalId);
    expect(second.idempotentReplay, isTrue);
    expect(await db.select(db.expenseReversals).get(), hasLength(1));
    expect(await db.select(db.journalEntries).get(), hasLength(2));
  });

  test('second distinct reversal is rejected without duplicate truth', () async {
    final sourceId = await postSource();
    await reverseExpense.execute(command(sourceExpenseId: sourceId));

    await expectLater(
      reverseExpense.execute(command(
        sourceExpenseId: sourceId,
        operationId: 'OP-EXR-2',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.expenseReversals).get(), hasLength(1));
    expect(await db.select(db.journalEntries).get(), hasLength(2));
    expect(await db.select(db.operationLog).get(), hasLength(2));
  });

  test('wrong-business reversal is rejected before compensating mutation', () async {
    final sourceId = await postSource();

    await expectLater(
      reverseExpense.execute(command(
        sourceExpenseId: sourceId,
        businessId: 'B-OTHER',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.expenseReversals).get(), isEmpty);
    final source = await db.select(db.expenses).getSingle();
    expect(source.status, 'posted');
    expect(await db.select(db.journalEntries).get(), hasLength(1));
  });

  test('blank reason is rejected before sequence allocation', () async {
    final sourceId = await postSource();

    await expectLater(
      reverseExpense.execute(command(sourceExpenseId: sourceId, reason: '   ')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.expenseReversals).get(), isEmpty);
    final sequences = await db.customSelect(
      "SELECT * FROM document_sequences WHERE document_type = 'expense_reversal'",
    ).get();
    expect(sequences, isEmpty);
  });
}
