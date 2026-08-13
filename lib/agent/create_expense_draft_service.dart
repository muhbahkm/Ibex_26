import '../core/errors/domain_error.dart';
import '../core/value_objects/money.dart';
import 'command_registry.dart';
import 'operational_draft.dart';

class CreateExpenseDraftRequest {
  const CreateExpenseDraftRequest({
    required this.draftId,
    required this.category,
    required this.amountText,
    required this.currencyCode,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.expenseLedgerAccountId,
    required this.createdAtUtc,
    this.description,
  });

  final String draftId;
  final String category;
  final String amountText;
  final String currencyCode;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String expenseLedgerAccountId;
  final DateTime createdAtUtc;
  final String? description;
}

class CreateExpenseDraftService {
  const CreateExpenseDraftService({required this.registry});

  static const commandName = 'CreateExpenseDraft';

  final AgentCommandRegistry registry;

  OperationalDraft execute(CreateExpenseDraftRequest request) {
    registry.requireRegistered(commandName);
    final draftId = request.draftId.trim();
    final category = request.category.trim();
    final cashAccountId = request.cashAccountId.trim();
    final cashLedgerAccountId = request.cashLedgerAccountId.trim();
    final expenseLedgerAccountId = request.expenseLedgerAccountId.trim();
    if (draftId.isEmpty ||
        category.isEmpty ||
        cashAccountId.isEmpty ||
        cashLedgerAccountId.isEmpty ||
        expenseLedgerAccountId.isEmpty) {
      throw const DomainError(
        'EXPENSE_DRAFT_REQUIRED_FIELDS',
        'Expense draft identity, category and account fields are required.',
      );
    }

    final amount = Money.parseExact(request.amountText, request.currencyCode);
    if (amount.isZero || amount.isNegative) {
      throw const DomainError(
        'EXPENSE_DRAFT_AMOUNT_INVALID',
        'Expense draft amount must be greater than zero.',
      );
    }

    final payload = <String, Object?>{
      'category': category,
      'description': request.description?.trim(),
      'currency_code': amount.currencyCode,
      'amount_scaled': amount.scaled,
      'cash_account_id': cashAccountId,
      'cash_ledger_account_id': cashLedgerAccountId,
      'expense_ledger_account_id': expenseLedgerAccountId,
    };

    return OperationalDraft(
      draftId: draftId,
      commandName: commandName,
      version: 1,
      payload: Map.unmodifiable(payload),
      state: OperationalDraftState.draftReady,
      createdAtUtc: request.createdAtUtc.toUtc(),
    ).markAwaitingApproval();
  }
}
