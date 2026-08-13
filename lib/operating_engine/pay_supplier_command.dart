class PaySupplierCommand {
  const PaySupplierCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.supplierId,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.amountScaled,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.accountsPayableLedgerAccountId,
    required this.paidAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String supplierId;
  final String currencyCode;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final int amountScaled;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String accountsPayableLedgerAccountId;
  final DateTime paidAt;
}

class PaySupplierResult {
  const PaySupplierResult({
    required this.paymentId,
    required this.documentNo,
    required this.journalEntryId,
    required this.idempotentReplay,
  });

  final String paymentId;
  final String documentNo;
  final String journalEntryId;
  final bool idempotentReplay;
}
