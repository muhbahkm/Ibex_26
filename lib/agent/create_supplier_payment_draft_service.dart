import '../core/errors/domain_error.dart';
import '../core/value_objects/money.dart';
import 'command_registry.dart';
import 'operational_draft.dart';

class CreateSupplierPaymentDraftRequest {
  const CreateSupplierPaymentDraftRequest({
    required this.draftId,
    required this.supplierId,
    required this.amountText,
    required this.currencyCode,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.accountsPayableLedgerAccountId,
    required this.createdAtUtc,
  });

  final String draftId;
  final String supplierId;
  final String amountText;
  final String currencyCode;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String accountsPayableLedgerAccountId;
  final DateTime createdAtUtc;
}

class CreateSupplierPaymentDraftService {
  const CreateSupplierPaymentDraftService({required this.registry});

  static const commandName = 'CreateSupplierPaymentDraft';

  final AgentCommandRegistry registry;

  OperationalDraft execute(CreateSupplierPaymentDraftRequest request) {
    registry.requireRegistered(commandName);
    final draftId = request.draftId.trim();
    final supplierId = request.supplierId.trim();
    final cashAccountId = request.cashAccountId.trim();
    final cashLedgerAccountId = request.cashLedgerAccountId.trim();
    final apAccountId = request.accountsPayableLedgerAccountId.trim();
    if (draftId.isEmpty ||
        supplierId.isEmpty ||
        cashAccountId.isEmpty ||
        cashLedgerAccountId.isEmpty ||
        apAccountId.isEmpty) {
      throw const DomainError(
        'SUPPLIER_PAYMENT_DRAFT_REQUIRED_FIELDS',
        'Supplier payment draft identity, supplier and accounts are required.',
      );
    }

    final amount = Money.parseExact(request.amountText, request.currencyCode);
    if (amount.isZero || amount.isNegative) {
      throw const DomainError(
        'SUPPLIER_PAYMENT_DRAFT_AMOUNT_INVALID',
        'Supplier payment draft amount must be greater than zero.',
      );
    }

    return OperationalDraft(
      draftId: draftId,
      commandName: commandName,
      version: 1,
      payload: Map.unmodifiable({
        'supplier_id': supplierId,
        'currency_code': amount.currencyCode,
        'amount_scaled': amount.scaled,
        'cash_account_id': cashAccountId,
        'cash_ledger_account_id': cashLedgerAccountId,
        'accounts_payable_ledger_account_id': apAccountId,
      }),
      state: OperationalDraftState.draftReady,
      createdAtUtc: request.createdAtUtc.toUtc(),
    ).markAwaitingApproval();
  }
}
