import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_supplier_payment_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_supplier_payment_draft_service.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/agent/supplier_payment_operational_workflow.dart';
import 'package:ibex_foundation_spike/core/id/stable_operation_id.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/pay_supplier_command.dart';

void main() {
  late SpikeDatabase db;
  late OperationalDraftRepository repository;
  final now = DateTime.utc(2026, 8, 11, 14);

  setUp(() {
    db = SpikeDatabase.inMemory();
    repository = OperationalDraftRepository(db);
  });

  tearDown(() => db.close());

  CreateSupplierPaymentDraftRequest request() =>
      CreateSupplierPaymentDraftRequest(
        draftId: 'D-PAY-1',
        supplierId: 'SUP-1',
        amountText: '250',
        currencyCode: 'SAR',
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        accountsPayableLedgerAccountId: 'ACC-AP',
        createdAtUtc: now,
      );

  SupplierPaymentPostingContext contextFor(OperationalDraft draft) =>
      SupplierPaymentPostingContext(
        operationId: StableOperationId.forApprovedDraft(
          commandName: 'PaySupplier',
          businessId: 'B-1',
          draftId: draft.draftId,
          version: draft.version,
          fingerprint: draft.fingerprint,
        ),
        businessId: 'B-1',
        userId: 'U-1',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        paidAt: now,
      );

  test('supplier payment cannot be previewed or executed before approval', () async {
    var calls = 0;
    final workflow = SupplierPaymentOperationalWorkflow(
      createSupplierPaymentDraft: const CreateSupplierPaymentDraftService(
        registry: AgentCommandRegistry({CreateSupplierPaymentDraftService.commandName}),
      ),
      draftRepository: repository,
      paySupplierExecutor: (_) async {
        calls++;
        return const PaySupplierResult(
          paymentId: 'PAY-1',
          documentNo: 'PAY-2026-000001',
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
    expect(calls, 0);

    final approved = await workflow.approve(draft.draftId);
    final preview = await workflow.previewPostingCommand(
      draftId: approved.draftId,
      context: contextFor(approved),
    );
    expect(preview.supplierId, 'SUP-1');
    expect(preview.amountScaled, 250 * 10000);
    expect(calls, 0);
  });

  test('failed authorized executor leaves approved payment draft retryable', () async {
    final workflow = SupplierPaymentOperationalWorkflow(
      createSupplierPaymentDraft: const CreateSupplierPaymentDraftService(
        registry: AgentCommandRegistry({CreateSupplierPaymentDraftService.commandName}),
      ),
      draftRepository: repository,
      paySupplierExecutor: (_) async => throw StateError('injected failure'),
    );

    final created = await workflow.create(request());
    final approved = await workflow.approve(created.draftId);
    await expectLater(
      workflow.postApproved(
        draftId: approved.draftId,
        context: contextFor(approved),
      ),
      throwsA(isA<StateError>()),
    );
    final stored = await repository.load(approved.draftId);
    expect(stored!.state, OperationalDraftState.approved);
    expect(stored.approvedFingerprint, stored.fingerprint);
  });
}
