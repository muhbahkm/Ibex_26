import '../core/errors/domain_error.dart';
import '../operating_engine/pay_supplier_command.dart';
import 'approved_supplier_payment_draft_to_command.dart';
import 'create_supplier_payment_draft_service.dart';
import 'operational_draft.dart';
import 'operational_draft_repository.dart';

typedef PaySupplierExecutor = Future<PaySupplierResult> Function(PaySupplierCommand command);

class SupplierPaymentOperationalWorkflow {
  SupplierPaymentOperationalWorkflow({
    required this.createSupplierPaymentDraft,
    required this.draftRepository,
    required this.paySupplierExecutor,
    ApprovedSupplierPaymentDraftToCommand mapper =
        const ApprovedSupplierPaymentDraftToCommand(),
  }) : _mapper = mapper;

  final CreateSupplierPaymentDraftService createSupplierPaymentDraft;
  final OperationalDraftRepository draftRepository;
  final PaySupplierExecutor paySupplierExecutor;
  final ApprovedSupplierPaymentDraftToCommand _mapper;

  Future<OperationalDraft> create(CreateSupplierPaymentDraftRequest request) async {
    final existing = await draftRepository.load(request.draftId.trim());
    if (existing != null) {
      throw const DomainError(
        'DRAFT_ID_ALREADY_EXISTS',
        'A draft with this identifier already exists.',
      );
    }
    final draft = createSupplierPaymentDraft.execute(request);
    await draftRepository.save(draft);
    return draft;
  }

  Future<OperationalDraft> loadRequired(String draftId) async {
    final draft = await draftRepository.load(draftId.trim());
    if (draft == null ||
        draft.commandName != CreateSupplierPaymentDraftService.commandName) {
      throw const DomainError(
        'SUPPLIER_PAYMENT_DRAFT_NOT_FOUND',
        'Supplier payment operational draft was not found.',
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

  Future<PaySupplierCommand> previewPostingCommand({
    required String draftId,
    required SupplierPaymentPostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    return _mapper.build(draft: approved, context: context);
  }

  Future<PaySupplierResult> postApproved({
    required String draftId,
    required SupplierPaymentPostingContext context,
  }) async {
    final approved = await loadRequired(draftId);
    final command = _mapper.build(draft: approved, context: context);
    final result = await paySupplierExecutor(command);
    await draftRepository.save(approved.markPosted());
    return result;
  }
}
