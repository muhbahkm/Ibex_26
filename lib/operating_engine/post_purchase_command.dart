enum PurchaseSettlementMode { cash, credit }

class PostPurchaseLineInput {
  const PostPurchaseLineInput({
    required this.productId,
    required this.quantityScaled,
    required this.unitCostScaled,
  });

  final String productId;
  final int quantityScaled;
  final int unitCostScaled;
}

class PostPurchaseCommand {
  const PostPurchaseCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.warehouseId,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.inventoryLedgerAccountId,
    required this.accountsPayableLedgerAccountId,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.purchaseAt,
    required this.lines,
    this.supplierId,
    this.settlementMode = PurchaseSettlementMode.cash,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String warehouseId;
  final String? supplierId;
  final PurchaseSettlementMode settlementMode;
  final String currencyCode;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final String inventoryLedgerAccountId;
  final String accountsPayableLedgerAccountId;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final DateTime purchaseAt;
  final List<PostPurchaseLineInput> lines;
}

class PostPurchaseResult {
  const PostPurchaseResult({
    required this.purchaseId,
    required this.documentNo,
    required this.journalEntryId,
    required this.stockMovementId,
    required this.paymentId,
    required this.idempotentReplay,
  });

  final String purchaseId;
  final String documentNo;
  final String journalEntryId;
  final String stockMovementId;
  final String? paymentId;
  final bool idempotentReplay;
}