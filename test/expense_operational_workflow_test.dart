import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_expense_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_expense_draft_service.dart';
import 'package:ibex_foundation_spike/agent/expense_operational_workflow.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/core/id/stable_operation_id.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_command.dart';

void main() {
  late SpikeDatabase db;
  late OperationalDraftRepository repository;
  final now = DateTime.utc(2026, 8, 11, 12);

  setUp(() {
    db = SpikeDatabase.inMemory();
    repository = OperationalDraftRepository(db);
  });

  tearDown(() => db.close());

  CreateExpenseDraftRequest request({String draftId = 'D-EXP-1'}) =>
      CreateExpenseDraftRequest(
        draftId: draftId,
        category: 'نقل',
        amountText: '125',
        currencyCode: 'SAR',
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        expenseLedgerAccountId: 'ACC-EXP',
        createdAtUtc: now,
        description: 'نقل طلبية',
      );

  ExpensePostingContext contextFor(OperationalDraft draft) => ExpensePostingContext(
        operationId: StableOperationId.forApprovedDraft(
          commandName: 'PostExpense',
          businessId: 'B-1',
          draftId: draft.draftId,
          version: draft.version,
          fingerprint: draft.fingerprint,
        ),
        businessId: 'B-1',
        userId: 'U-1',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        expenseAt: now,
      );

  test('draft must be explicitly approved before typed expense command exists', () async {
    var executorCalls = 0;
    final workflow = ExpenseOperationalWorkflow(
      createExpenseDraft: const CreateExpenseDraftService(
        registry: AgentCommandRegistry({CreateExpenseDraftService.commandName}),
      ),
      draftRepository: repository,
      postExpenseExecutor: (command) async {
        executorCalls++;
        return const PostExpenseResult(
          expenseId: 'EXP-1',
          documentNo: 'EXP-2026-000001',
          journalEntryId: 'JE-1',
          idempotentReplay: false,
        );
      },
    );

    final draft = await workflow.create(request());
    expect(draft.state, OperationalDraftState.awaitingApproval);

    await expectLater(
      workflow.previewPostingCommand(
        draftId: draft.draftId,
        context: contextFor(draft),
      ),
      throwsA(isA<Exception>()),
    );
    expect(executorCalls, 0);

    final approved = await workflow.approve(draft.draftId);
    final preview = await workflow.previewPostingCommand(
      draftId: approved.draftId,
      context: contextFor(approved),
    );
    expect(preview.category, 'نقل');
    expect(preview.amountScaled, 125 * 10000);
    expect(preview.operationId, contextFor(approved).operationId);
    expect(executorCalls, 0);
  });

  test('posting invokes only injected authorized executor then persists terminal state', () async {
    PostExpenseCommand? executed;
    final workflow = ExpenseOperationalWorkflow(
      createExpenseDraft: const CreateExpenseDraftService(
        registry: AgentCommandRegistry({CreateExpenseDraftService.commandName}),
      ),
      draftRepository: repository,
      postExpenseExecutor: (command) async {
        executed = command;
        return const PostExpenseResult(
          expenseId: 'EXP-1',
          documentNo: 'EXP-2026-000001',
          journalEntryId: 'JE-1',
          idempotentReplay: false,
        );
      },
    );

    final created = await workflow.create(request());
    final approved = await workflow.approve(created.draftId);
    final context = contextFor(approved);
    final result = await workflow.postApproved(
      draftId: approved.draftId,
      context: context,
    );

    expect(result.expenseId, 'EXP-1');
    expect(executed, isNotNull);
    expect(executed!.operationId, context.operationId);
    final stored = await repository.load(approved.draftId);
    expect(stored!.state, OperationalDraftState.posted);
  });

  test('executor failure leaves approved draft retryable and never marks false posted truth', () async {
    final workflow = ExpenseOperationalWorkflow(
      createExpenseDraft: const CreateExpenseDraftService(
        registry: AgentCommandRegistry({CreateExpenseDraftService.commandName}),
      ),
      draftRepository: repository,
      postExpenseExecutor: (_) async => throw StateError('injected failure'),
    );

    final created = await workflow.create(request());
    final approved = await workflow.approve(created.draftId);

    await expectLater(
      workflow.postApproved(
        draftId: approved.draftId,
        context: contextFor(approved),
      ),
      throwsStateError,
    );
    final stored = await repository.load(approved.draftId);
    expect(stored!.state, OperationalDraftState.approved);
    expect(stored.approvedFingerprint, stored.fingerprint);
  });

  test('duplicate draft id is rejected without overwriting prior draft', () async {
    final workflow = ExpenseOperationalWorkflow(
      createExpenseDraft: const CreateExpenseDraftService(
        registry: AgentCommandRegistry({CreateExpenseDraftService.commandName}),
      ),
      draftRepository: repository,
      postExpenseExecutor: (_) async => throw UnimplementedError(),
    );

    final original = await workflow.create(request());
    await expectLater(workflow.create(request()), throwsA(isA<Exception>()));

    final stored = await repository.load(original.draftId);
    expect(stored, isNotNull);
    expect(stored!.draftId, original.draftId);
    expect(stored.version, original.version);
    expect(stored.fingerprint, original.fingerprint);
    expect(stored.state, OperationalDraftState.awaitingApproval);

    final count = await db.customSelect(
      'SELECT COUNT(*) AS draft_count FROM operational_draft_records WHERE draft_id = ?',
      variables: [
        const Variable<String>('D-EXP-1'),
      ],
    ).getSingle();
    expect(count.read<int>('draft_count'), 1);
  });
}
