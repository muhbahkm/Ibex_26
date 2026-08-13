import '../core/errors/domain_error.dart';
import '../operating_engine/post_expense_command.dart';
import 'create_expense_draft_service.dart';
import 'operational_draft.dart';

class ExpensePostingContext {
  const ExpensePostingContext({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.expenseAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final DateTime expenseAt;
}

class ApprovedExpenseDraftToCommand {
  const ApprovedExpenseDraftToCommand();

  PostExpenseCommand build({
    required OperationalDraft draft,
    required ExpensePostingContext context,
  }) {
    if (draft.commandName != CreateExpenseDraftService.commandName) {
      throw const DomainError(
        'EXPENSE_DRAFT_COMMAND_INVALID',
        'Only CreateExpenseDraft drafts can become PostExpense commands.',
      );
    }
    draft.requireValidApprovalForPosting();

    final category = draft.payload['category'];
    final description = draft.payload['description'];
    final currencyCode = draft.payload['currency_code'];
    final amountScaled = draft.payload['amount_scaled'];
    final cashAccountId = draft.payload['cash_account_id'];
    final cashLedgerAccountId = draft.payload['cash_ledger_account_id'];
    final expenseLedgerAccountId = draft.payload['expense_ledger_account_id'];
    if (category is! String ||
        category.trim().isEmpty ||
        currencyCode is! String ||
        amountScaled is! int ||
        amountScaled <= 0 ||
        cashAccountId is! String ||
        cashAccountId.trim().isEmpty ||
        cashLedgerAccountId is! String ||
        cashLedgerAccountId.trim().isEmpty ||
        expenseLedgerAccountId is! String ||
        expenseLedgerAccountId.trim().isEmpty ||
        (description != null && description is! String)) {
      throw const DomainError(
        'EXPENSE_DRAFT_PAYLOAD_INVALID',
        'Approved expense draft is missing posting fields.',
      );
    }

    return PostExpenseCommand(
      operationId: context.operationId,
      businessId: context.businessId,
      userId: context.userId,
      category: category,
      description: description as String?,
      currencyCode: currencyCode,
      baseCurrencyCode: context.baseCurrencyCode,
      exchangeRateScaled: context.exchangeRateScaled,
      amountScaled: amountScaled,
      cashAccountId: cashAccountId,
      cashLedgerAccountId: cashLedgerAccountId,
      expenseLedgerAccountId: expenseLedgerAccountId,
      expenseAt: context.expenseAt,
    );
  }
}
