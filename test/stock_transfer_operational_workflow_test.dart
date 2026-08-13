import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_stock_transfer_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_stock_transfer_draft_service.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/agent/stock_transfer_operational_workflow.dart';
import 'package:ibex_foundation_spike/core/id/stable_operation_id.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/transfer_stock_command.dart';

void main() {
  late SpikeDatabase db;
  late OperationalDraftRepository repository;
  final now = DateTime.utc(2026, 8, 11, 15);

  setUp(() {
    db = SpikeDatabase.inMemory();
    repository = OperationalDraftRepository(db);
  });

  tearDown(() => db.close());

  CreateStockTransferDraftRequest request({
    String source = 'WH-1',
    String destination = 'WH-2',
  }) => CreateStockTransferDraftRequest(
        draftId: 'D-STX-1',
        sourceWarehouseId: source,
        destinationWarehouseId: destination,
        productId: 'P-1',
        quantityText: '3',
        quantityPrecision: 0,
        createdAtUtc: now,
      );

  StockTransferPostingContext contextFor(OperationalDraft draft) =>
      StockTransferPostingContext(
        operationId: StableOperationId.forApprovedDraft(
          commandName: 'TransferStock',
          businessId: 'B-1',
          draftId: draft.draftId,
          version: draft.version,
          fingerprint: draft.fingerprint,
        ),
        businessId: 'B-1',
        userId: 'U-1',
        transferredAt: now,
      );

  test('stock transfer cannot reach executor before explicit approval', () async {
    var calls = 0;
    final workflow = StockTransferOperationalWorkflow(
      createStockTransferDraft: const CreateStockTransferDraftService(
        registry: AgentCommandRegistry({CreateStockTransferDraftService.commandName}),
      ),
      draftRepository: repository,
      transferStockExecutor: (_) async {
        calls++;
        return const TransferStockResult(
          transferId: 'STX-1',
          documentNo: 'STX-2026-000001',
          sourceMovementId: 'SM-OUT',
          destinationMovementId: 'SM-IN',
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
    expect(preview.sourceWarehouseId, 'WH-1');
    expect(preview.destinationWarehouseId, 'WH-2');
    expect(preview.lines.single.quantityScaled, 3 * 1000000);
    expect(calls, 0);
  });

  test('same source and destination are rejected before draft persistence', () async {
    final workflow = StockTransferOperationalWorkflow(
      createStockTransferDraft: const CreateStockTransferDraftService(
        registry: AgentCommandRegistry({CreateStockTransferDraftService.commandName}),
      ),
      draftRepository: repository,
      transferStockExecutor: (_) async => throw UnimplementedError(),
    );

    await expectLater(
      workflow.create(request(source: 'WH-1', destination: 'WH-1')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.operationalDraftRecords).get(), isEmpty);
  });

  test('executor failure keeps approved transfer draft retryable', () async {
    final workflow = StockTransferOperationalWorkflow(
      createStockTransferDraft: const CreateStockTransferDraftService(
        registry: AgentCommandRegistry({CreateStockTransferDraftService.commandName}),
      ),
      draftRepository: repository,
      transferStockExecutor: (_) async => throw StateError('injected failure'),
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
