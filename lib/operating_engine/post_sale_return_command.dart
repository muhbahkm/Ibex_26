class PostSaleReturnLineInput {
  const PostSaleReturnLineInput({
    required this.sourceSaleItemId,
    required this.quantityScaled,
  });

  final String sourceSaleItemId;
  final int quantityScaled;
}

class PostSaleReturnCommand {
  const PostSaleReturnCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.sourceSaleId,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.salesRevenueAccountId,
    required this.inventoryLedgerAccountId,
    required this.cogsLedgerAccountId,
    required this.accountsReceivableLedgerAccountId,
    required this.returnedAt,
    required this.lines,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String sourceSaleId;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String salesRevenueAccountId;
  final String inventoryLedgerAccountId;
  final String cogsLedgerAccountId;
  final String accountsReceivableLedgerAccountId;
  final DateTime returnedAt;
  final List<PostSaleReturnLineInput> lines;
}

class PostSaleReturnResult {
  const PostSaleReturnResult({
    required this.saleReturnId,
    required this.documentNo,
    required this.journalEntryId,
    required this.stockMovementId,
    required this.refundPaymentId,
    required this.idempotentReplay,
  });

  final String saleReturnId;
  final String documentNo;
  final String journalEntryId;
  final String stockMovementId;
  final String? refundPaymentId;
  final bool idempotentReplay;
}
