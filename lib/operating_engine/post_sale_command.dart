enum SaleSettlementMode { cash, credit }

class PostSaleLineInput {
  const PostSaleLineInput({
    required this.productId,
    required this.quantityScaled,
    required this.unitPriceScaled,
  });

  final String productId;
  final int quantityScaled;
  final int unitPriceScaled;
}

class PostSaleCommand {
  const PostSaleCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.warehouseId,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.salesRevenueAccountId,
    required this.inventoryLedgerAccountId,
    required this.cogsLedgerAccountId,
    required this.saleAt,
    required this.lines,
    this.customerId,
    this.settlementMode = SaleSettlementMode.cash,
    this.accountsReceivableLedgerAccountId = 'ACC-AR',
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String warehouseId;
  final String currencyCode;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String salesRevenueAccountId;
  final String inventoryLedgerAccountId;
  final String cogsLedgerAccountId;
  final String accountsReceivableLedgerAccountId;
  final String? customerId;
  final SaleSettlementMode settlementMode;
  final DateTime saleAt;
  final List<PostSaleLineInput> lines;
}

class PostSaleResult {
  const PostSaleResult({
    required this.saleId,
    required this.documentNo,
    required this.journalEntryId,
    required this.stockMovementId,
    required this.paymentId,
    required this.idempotentReplay,
  });

  final String saleId;
  final String documentNo;
  final String journalEntryId;
  final String stockMovementId;
  final String? paymentId;
  final bool idempotentReplay;
}
