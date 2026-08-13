class PostExpenseCommand {
  const PostExpenseCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.category,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.amountScaled,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.expenseLedgerAccountId,
    required this.expenseAt,
    this.description,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String category;
  final String? description;
  final String currencyCode;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final int amountScaled;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String expenseLedgerAccountId;
  final DateTime expenseAt;
}

class PostExpenseResult {
  const PostExpenseResult({
    required this.expenseId,
    required this.documentNo,
    required this.journalEntryId,
    required this.idempotentReplay,
  });

  final String expenseId;
  final String documentNo;
  final String journalEntryId;
  final bool idempotentReplay;
}
