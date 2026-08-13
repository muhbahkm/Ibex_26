import '../core/errors/domain_error.dart';
import '../operating_engine/transfer_stock_command.dart';
import 'approved_stock_transfer_draft_to_command.dart';
import 'create_stock_transfer_draft_service.dart';
import 'operational_draft.dart';
import 'operational_draft_repository.dart';

typedef TransferStockExecutor = Future<TransferStockResult> Function(TransferStockCommand command);

class StockTransferOperationalWorkflow {
  StockTransferOperationalWorkflow({
    required this.createStockTransferDraft,
    required this.draftRepository,
    required this.transferStockExecutor,
    ApprovedStockTransferDraftToCommand mapper = const ApprovedStockTransferDraftToCommand(),
  }) : _mapper = mapper;

  final CreateStockTransferDraftService createStockTransferDraft;
  final OperationalDraftRepository draftRepository;
  final TransferStockExecutor transferStockExecutor;
  final ApprovedStockTransferDraftToCommand _mapper;

  Future<OperationalDraft> create(CreateStockTransferDraftRequest request) async {
    final existing = await draftRepository.load(request.draftId.trim());
    if (existing != null) {
      throw const DomainError(
        'DRAFT_ID_ALREADY_EXISTS',
        'A draft with this identifier already exists.',
      );
    }
    final draft = createStockTransferDraft.execute(request);
    await draftRepository.save(draft);
    return draft;
  }

  Future<OperationalDraft> loadRequired(String draftId) async {
    final draft = await draftRepository.load(draftId.trim());
    if (draft == null || draft.commandName != CreateStockTransferDraftService.commandName) {
      throw const DomainError(
        'STOCK_TRANSFER_DRAFT_NOT_FOUND',
        'Stock transfer operational draft was not found.',
      );
    }
    return draft;
  }

  Future<OperationalDraft> approve(String draftId) async {
    final current = await loadRequired(draftId);
    final approved = current.approve();
    await draftRepository.save(approved);
    return approved;
  }

  Future<OperationalDraft> cancel(String draftId) async {
    final current = await loadRequired(draftId);
    final cancelled = current.cancel();
    await draftRepository.save(cancelled);
    return cancelled;
  }

  Future<TransferStockCommand> previewPostingCommand({
    required String draftId,
    required StockTransferPostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    return _mapper.build(draft: approved, context: context);
  }

  Future<TransferStockResult> postApproved({
    required String draftId,
    required StockTransferPostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    final command = _mapper.build(draft: approved, context: context);
    final result = await transferStockExecutor(command);
    await draftRepository.save(approved.markPosted());
    return result;
  }
}
