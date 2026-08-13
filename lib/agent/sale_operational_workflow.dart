import '../core/errors/domain_error.dart';
import '../operating_engine/post_sale_command.dart';
import '../operating_engine/post_sale_service.dart';
import 'approved_sale_draft_to_command.dart';
import 'create_sale_draft_service.dart';
import 'operational_draft.dart';
import 'operational_draft_repository.dart';
import 'revise_sale_draft_service.dart';

typedef PostSaleExecutor = Future<PostSaleResult> Function(PostSaleCommand command);

class SaleOperationalWorkflow {
  SaleOperationalWorkflow({
    required this.createSaleDraft,
    required this.draftRepository,
    required this.postSaleService,
    PostSaleExecutor? postSaleExecutor,
    ReviseSaleDraftService reviseSaleDraft = const ReviseSaleDraftService(),
    ApprovedSaleDraftToCommand mapper = const ApprovedSaleDraftToCommand(),
  })  : _postSaleExecutor = postSaleExecutor ?? postSaleService.execute,
        _reviseSaleDraft = reviseSaleDraft,
        _mapper = mapper;

  final CreateSaleDraftService createSaleDraft;
  final OperationalDraftRepository draftRepository;
  final PostSaleService postSaleService;
  final PostSaleExecutor _postSaleExecutor;
  final ReviseSaleDraftService _reviseSaleDraft;
  final ApprovedSaleDraftToCommand _mapper;

  Future<OperationalDraft> create(CreateSaleDraftRequest request) async {
    final existing = await draftRepository.load(request.draftId.trim());
    if (existing != null) {
      throw const DomainError(
        'DRAFT_ID_ALREADY_EXISTS',
        'A draft with this identifier already exists.',
      );
    }
    final draft = await createSaleDraft.execute(request);
    await draftRepository.save(draft);
    return draft;
  }

  Future<OperationalDraft?> loadLatestOpen() =>
      draftRepository.loadLatestOpen(commandName: CreateSaleDraftService.commandName);

  Future<OperationalDraft> loadRequired(String draftId) async {
    final draft = await draftRepository.load(draftId.trim());
    if (draft == null) {
      throw const DomainError('DRAFT_NOT_FOUND', 'Operational draft was not found.');
    }
    return draft;
  }

  Future<OperationalDraft> approve(String draftId) async {
    final current = await loadRequired(draftId);
    final approved = current.approve();
    await draftRepository.save(approved);
    return approved;
  }

  Future<OperationalDraft> revisePrice(String draftId, String unitPriceText) async {
    final current = await loadRequired(draftId);
    final revised = _reviseSaleDraft.execute(
      ReviseSaleDraftRequest(draft: current, unitPriceText: unitPriceText),
    );
    await draftRepository.save(revised);
    return revised;
  }

  Future<OperationalDraft> reviseQuantity(String draftId, String quantityText) async {
    final current = await loadRequired(draftId);
    final revised = _reviseSaleDraft.execute(
      ReviseSaleDraftRequest(draft: current, quantityText: quantityText),
    );
    await draftRepository.save(revised);
    return revised;
  }

  Future<OperationalDraft> cancel(String draftId) async {
    final current = await loadRequired(draftId);
    final cancelled = current.cancel();
    await draftRepository.save(cancelled);
    return cancelled;
  }

  Future<PostSaleResult> postApproved({
    required String draftId,
    required SalePostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    final command = _mapper.build(draft: approved, context: context);
    final result = await _postSaleExecutor(command);

    // Persist the posted terminal state only after the authorized Operating
    // Engine executor commits. If posting fails, the approved draft remains
    // retryable and no false posted state is stored.
    final posted = approved.markPosted();
    await draftRepository.save(posted);
    return result;
  }

  Future<PostSaleCommand> previewPostingCommand({
    required String draftId,
    required SalePostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    return _mapper.build(draft: approved, context: context);
  }
}
