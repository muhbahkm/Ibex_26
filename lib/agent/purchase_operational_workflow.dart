import '../core/errors/domain_error.dart';
import '../operating_engine/post_purchase_command.dart';
import 'approved_purchase_draft_to_command.dart';
import 'create_purchase_draft_service.dart';
import 'operational_draft.dart';
import 'operational_draft_repository.dart';

typedef PostPurchaseExecutor = Future<PostPurchaseResult> Function(PostPurchaseCommand command);

class PurchaseOperationalWorkflow {
  PurchaseOperationalWorkflow({
    required this.createPurchaseDraft,
    required this.draftRepository,
    required this.postPurchaseExecutor,
    ApprovedPurchaseDraftToCommand mapper = const ApprovedPurchaseDraftToCommand(),
  }) : _mapper = mapper;

  final CreatePurchaseDraftService createPurchaseDraft;
  final OperationalDraftRepository draftRepository;
  final PostPurchaseExecutor postPurchaseExecutor;
  final ApprovedPurchaseDraftToCommand _mapper;

  Future<OperationalDraft> create(CreatePurchaseDraftRequest request) async {
    final existing = await draftRepository.load(request.draftId.trim());
    if (existing != null) {
      throw const DomainError(
        'DRAFT_ID_ALREADY_EXISTS',
        'A draft with this identifier already exists.',
      );
    }
    final draft = createPurchaseDraft.execute(request);
    await draftRepository.save(draft);
    return draft;
  }

  Future<OperationalDraft> loadRequired(String draftId) async {
    final draft = await draftRepository.load(draftId.trim());
    if (draft == null || draft.commandName != CreatePurchaseDraftService.commandName) {
      throw const DomainError(
        'PURCHASE_DRAFT_NOT_FOUND',
        'Purchase operational draft was not found.',
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

  Future<PostPurchaseCommand> previewPostingCommand({
    required String draftId,
    required PurchasePostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    return _mapper.build(draft: approved, context: context);
  }

  Future<PostPurchaseResult> postApproved({
    required String draftId,
    required PurchasePostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    final command = _mapper.build(draft: approved, context: context);
    final result = await postPurchaseExecutor(command);
    await draftRepository.save(approved.markPosted());
    return result;
  }
}
