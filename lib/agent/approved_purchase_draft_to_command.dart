import '../core/errors/domain_error.dart';
import '../operating_engine/post_purchase_command.dart';
import 'create_purchase_draft_service.dart';
import 'operational_draft.dart';

class PurchasePostingContext {
  const PurchasePostingContext({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.inventoryLedgerAccountId,
    required this.accountsPayableLedgerAccountId,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.purchaseAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final String inventoryLedgerAccountId;
  final String accountsPayableLedgerAccountId;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final DateTime purchaseAt;
}

class ApprovedPurchaseDraftToCommand {
  const ApprovedPurchaseDraftToCommand();

  PostPurchaseCommand build({
    required OperationalDraft draft,
    required PurchasePostingContext context,
  }) {
    if (draft.commandName != CreatePurchaseDraftService.commandName) {
      throw const DomainError(
        'PURCHASE_DRAFT_COMMAND_INVALID',
        'Only CreatePurchaseDraft drafts can become PostPurchase commands.',
      );
    }
    draft.requireValidApprovalForPosting();

    final warehouseId = draft.payload['warehouse_id'];
    final supplierId = draft.payload['supplier_id'];
    final settlementRaw = draft.payload['settlement_mode'];
    final currencyCode = draft.payload['currency_code'];
    final linesRaw = draft.payload['lines'];
    if (warehouseId is! String ||
        warehouseId.trim().isEmpty ||
        (supplierId != null && supplierId is! String) ||
        settlementRaw is! String ||
        currencyCode is! String ||
        linesRaw is! List ||
        linesRaw.isEmpty) {
      throw const DomainError(
        'PURCHASE_DRAFT_PAYLOAD_INVALID',
        'Approved purchase draft is missing posting fields.',
      );
    }

    final settlement = switch (settlementRaw.trim().toLowerCase()) {
      'cash' => PurchaseSettlementMode.cash,
      'credit' => PurchaseSettlementMode.credit,
      _ => throw const DomainError(
          'PURCHASE_SETTLEMENT_MODE_INVALID',
          'Approved purchase draft contains an unsupported settlement mode.',
        ),
    };
    if (settlement == PurchaseSettlementMode.credit &&
        (supplierId == null || (supplierId as String).trim().isEmpty)) {
      throw const DomainError(
        'PURCHASE_CREDIT_SUPPLIER_REQUIRED',
        'Credit purchase requires a supplier.',
      );
    }

    final lines = <PostPurchaseLineInput>[];
    for (final raw in linesRaw) {
      if (raw is! Map) {
        throw const DomainError(
          'PURCHASE_DRAFT_LINE_INVALID',
          'Approved purchase draft contains an invalid line.',
        );
      }
      final productId = raw['product_id'];
      final quantityScaled = raw['quantity_scaled'];
      final unitCostScaled = raw['unit_cost_scaled'];
      if (productId is! String ||
          productId.trim().isEmpty ||
          quantityScaled is! int ||
          quantityScaled <= 0 ||
          unitCostScaled is! int ||
          unitCostScaled <= 0) {
        throw const DomainError(
          'PURCHASE_DRAFT_LINE_INVALID',
          'Approved purchase draft contains invalid posting values.',
        );
      }
      lines.add(
        PostPurchaseLineInput(
          productId: productId,
          quantityScaled: quantityScaled,
          unitCostScaled: unitCostScaled,
        ),
      );
    }

    return PostPurchaseCommand(
      operationId: context.operationId,
      businessId: context.businessId,
      userId: context.userId,
      warehouseId: warehouseId,
      supplierId: supplierId as String?,
      settlementMode: settlement,
      currencyCode: currencyCode,
      baseCurrencyCode: context.baseCurrencyCode,
      exchangeRateScaled: context.exchangeRateScaled,
      inventoryLedgerAccountId: context.inventoryLedgerAccountId,
      accountsPayableLedgerAccountId: context.accountsPayableLedgerAccountId,
      cashAccountId: context.cashAccountId,
      cashLedgerAccountId: context.cashLedgerAccountId,
      purchaseAt: context.purchaseAt,
      lines: List.unmodifiable(lines),
    );
  }
}
