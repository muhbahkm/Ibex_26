import '../core/errors/domain_error.dart';
import '../operating_engine/pay_supplier_command.dart';
import 'create_supplier_payment_draft_service.dart';
import 'operational_draft.dart';

class SupplierPaymentPostingContext {
  const SupplierPaymentPostingContext({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.paidAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final DateTime paidAt;
}

class ApprovedSupplierPaymentDraftToCommand {
  const ApprovedSupplierPaymentDraftToCommand();

  PaySupplierCommand build({
    required OperationalDraft draft,
    required SupplierPaymentPostingContext context,
  }) {
    if (draft.commandName != CreateSupplierPaymentDraftService.commandName) {
      throw const DomainError(
        'SUPPLIER_PAYMENT_DRAFT_COMMAND_INVALID',
        'Only CreateSupplierPaymentDraft drafts can become PaySupplier commands.',
      );
    }
    draft.requireValidApprovalForPosting();

    final supplierId = draft.payload['supplier_id'];
    final currencyCode = draft.payload['currency_code'];
    final amountScaled = draft.payload['amount_scaled'];
    final cashAccountId = draft.payload['cash_account_id'];
    final cashLedgerAccountId = draft.payload['cash_ledger_account_id'];
    final apAccountId = draft.payload['accounts_payable_ledger_account_id'];
    if (supplierId is! String ||
        supplierId.trim().isEmpty ||
        currencyCode is! String ||
        amountScaled is! int ||
        amountScaled <= 0 ||
        cashAccountId is! String ||
        cashAccountId.trim().isEmpty ||
        cashLedgerAccountId is! String ||
        cashLedgerAccountId.trim().isEmpty ||
        apAccountId is! String ||
        apAccountId.trim().isEmpty) {
      throw const DomainError(
        'SUPPLIER_PAYMENT_DRAFT_PAYLOAD_INVALID',
        'Approved supplier payment draft is missing posting fields.',
      );
    }

    return PaySupplierCommand(
      operationId: context.operationId,
      businessId: context.businessId,
      userId: context.userId,
      supplierId: supplierId,
      currencyCode: currencyCode,
      baseCurrencyCode: context.baseCurrencyCode,
      exchangeRateScaled: context.exchangeRateScaled,
      amountScaled: amountScaled,
      cashAccountId: cashAccountId,
      cashLedgerAccountId: cashLedgerAccountId,
      accountsPayableLedgerAccountId: apAccountId,
      paidAt: context.paidAt,
    );
  }
}
