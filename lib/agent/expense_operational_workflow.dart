import '../core/errors/domain_error.dart';
import '../operating_engine/post_expense_command.dart';
import 'approved_expense_draft_to_command.dart';
import 'create_expense_draft_service.dart';
import 'operational_draft.dart';
import 'operational_draft_repository.dart';

typedef PostExpenseExecutor = Future<PostExpenseResult> Function(PostExpenseCommand command);

class ExpenseOperationalWorkflow {
  ExpenseOperationalWorkflow({
    required this.createExpenseDraft,
    required this.draftRepository,
    required this.postExpenseExecutor,
    ApprovedExpenseDraftToCommand mapper = const ApprovedExpenseDraftToCommand(),
  }) : _mapper = mapper;

  final CreateExpenseDraftService createExpenseDraft;
  final OperationalDraftRepository draftRepository;
  final PostExpenseExecutor postExpenseExecutor;
  final ApprovedExpenseDraftToCommand _mapper;

  Future<OperationalDraft> create(CreateExpenseDraftRequest request) async {
    final existing = await draftRepository.load(request.draftId.trim());
    if (existing != null) {
      throw const DomainError(
        'DRAFT_ID_ALREADY_EXISTS',
        'A draft with this identifier already exists.',
      );
    }
    final draft = createExpenseDraft.execute(request);
    await draftRepository.save(draft);
    return draft;
  }

  Future<OperationalDraft> loadRequired(String draftId) async {
    final draft = await draftRepository.load(draftId.trim());
    if (draft == null || draft.commandName != CreateExpenseDraftService.commandName) {
      throw const DomainError(
        'EXPENSE_DRAFT_NOT_FOUND',
        'Expense operational draft was not found.',
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

  Future<PostExpenseCommand> previewPostingCommand({
    required String draftId,
    required ExpensePostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    return _mapper.build(draft: approved, context: context);
  }

  Future<PostExpenseResult> postApproved({
    required String draftId,
    required ExpensePostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    final command = _mapper.build(draft: approved, context: context);
    final result = await postExpenseExecutor(command);

    final posted = approved.markPosted();
    await draftRepository.save(posted);
    return result;
  }
}
