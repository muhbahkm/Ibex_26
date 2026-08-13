class PostPurchaseReturnLineInput {
  const PostPurchaseReturnLineInput({
    required this.sourcePurchaseItemId,
    required this.quantityScaled,
  });

  final String sourcePurchaseItemId;
  final int quantityScaled;
}

class PostPurchaseReturnCommand {
  const PostPurchaseReturnCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.sourcePurchaseId,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.inventoryLedgerAccountId,
    required this.accountsPayableLedgerAccountId,
    required this.returnedAt,
    required this.lines,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String sourcePurchaseId;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String inventoryLedgerAccountId;
  final String accountsPayableLedgerAccountId;
  final DateTime returnedAt;
  final List<PostPurchaseReturnLineInput> lines;
}

class PostPurchaseReturnResult {
  const PostPurchaseReturnResult({
    required this.purchaseReturnId,
    required this.documentNo,
    required this.journalEntryId,
    required this.stockMovementId,
    required this.cashReceiptId,
    required this.idempotentReplay,
  });

  final String purchaseReturnId;
  final String documentNo;
  final String journalEntryId;
  final String stockMovementId;
  final String? cashReceiptId;
  final bool idempotentReplay;
}
