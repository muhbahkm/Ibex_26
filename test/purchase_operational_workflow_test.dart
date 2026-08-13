import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_purchase_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_purchase_draft_service.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/agent/purchase_operational_workflow.dart';
import 'package:ibex_foundation_spike/core/id/stable_operation_id.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_command.dart';

void main() {
  late SpikeDatabase db;
  late OperationalDraftRepository repository;
  final now = DateTime.utc(2026, 8, 11, 13);

  setUp(() {
    db = SpikeDatabase.inMemory();
    repository = OperationalDraftRepository(db);
  });

  tearDown(() => db.close());

  CreatePurchaseDraftRequest request({
    String draftId = 'D-PUR-1',
    String settlementMode = 'credit',
    String? supplierId = 'SUP-1',
  }) =>
      CreatePurchaseDraftRequest(
        draftId: draftId,
        warehouseId: 'WH-1',
        supplierId: supplierId,
        productId: 'P-1',
        quantityText: '2',
        quantityPrecision: 0,
        unitCostText: '100',
        currencyCode: 'SAR',
        createdAtUtc: now,
        settlementMode: settlementMode,
      );

  PurchasePostingContext contextFor(OperationalDraft draft) => PurchasePostingContext(
        operationId: StableOperationId.forApprovedDraft(
          commandName: 'PostPurchase',
          businessId: 'B-1',
          draftId: draft.draftId,
          version: draft.version,
          fingerprint: draft.fingerprint,
        ),
        businessId: 'B-1',
        userId: 'U-1',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        inventoryLedgerAccountId: 'ACC-INV',
        accountsPayableLedgerAccountId: 'ACC-AP',
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        purchaseAt: now,
      );

  test('purchase posting command cannot be previewed before approval', () async {
    var calls = 0;
    final workflow = PurchaseOperationalWorkflow(
      createPurchaseDraft: const CreatePurchaseDraftService(
        registry: AgentCommandRegistry({CreatePurchaseDraftService.commandName}),
      ),
      draftRepository: repository,
      postPurchaseExecutor: (_) async {
        calls++;
        return const PostPurchaseResult(
          purchaseId: 'PUR-1',
          documentNo: 'PUR-2026-000001',
          journalEntryId: 'JE-1',
          stockMovementId: 'SM-1',
          paymentId: null,
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
    expect(preview.settlementMode, PurchaseSettlementMode.credit);
    expect(preview.supplierId, 'SUP-1');
    expect(preview.lines.single.quantityScaled, 2 * 1000000);
    expect(calls, 0);
  });

  test('credit purchase draft without supplier fails before persistence', () async {
    final workflow = PurchaseOperationalWorkflow(
      createPurchaseDraft: const CreatePurchaseDraftService(
        registry: AgentCommandRegistry({CreatePurchaseDraftService.commandName}),
      ),
      draftRepository: repository,
      postPurchaseExecutor: (_) async => throw UnimplementedError(),
    );

    await expectLater(
      workflow.create(request(supplierId: null)),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.operationalDraftRecords).get(), isEmpty);
  });

  test('executor failure preserves approved purchase draft for retry', () async {
    final workflow = PurchaseOperationalWorkflow(
      createPurchaseDraft: const CreatePurchaseDraftService(
        registry: AgentCommandRegistry({CreatePurchaseDraftService.commandName}),
      ),
      draftRepository: repository,
      postPurchaseExecutor: (_) async => throw StateError('injected failure'),
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
}
