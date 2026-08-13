class ReverseExpenseCommand {
  const ReverseExpenseCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.sourceExpenseId,
    required this.reason,
    required this.reversedAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String sourceExpenseId;
  final String reason;
  final DateTime reversedAt;
}

class ReverseExpenseResult {
  const ReverseExpenseResult({
    required this.expenseReversalId,
    required this.documentNo,
    required this.journalEntryId,
    required this.idempotentReplay,
  });

  final String expenseReversalId;
  final String documentNo;
  final String journalEntryId;
  final bool idempotentReplay;
}
