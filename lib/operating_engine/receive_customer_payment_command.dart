class ReceiveCustomerPaymentCommand {
  const ReceiveCustomerPaymentCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.customerId,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.amountScaled,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.accountsReceivableLedgerAccountId,
    required this.receivedAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String customerId;
  final String currencyCode;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final int amountScaled;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String accountsReceivableLedgerAccountId;
  final DateTime receivedAt;
}

class ReceiveCustomerPaymentResult {
  const ReceiveCustomerPaymentResult({
    required this.receiptId,
    required this.documentNo,
    required this.journalEntryId,
    required this.idempotentReplay,
  });

  final String receiptId;
  final String documentNo;
  final String journalEntryId;
  final bool idempotentReplay;
}
