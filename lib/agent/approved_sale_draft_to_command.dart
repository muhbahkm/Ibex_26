import '../core/errors/domain_error.dart';
import '../operating_engine/post_sale_command.dart';
import 'operational_draft.dart';

class SalePostingContext {
  const SalePostingContext({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.baseCurrencyCode,
    required this.exchangeRateScaled,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.salesRevenueAccountId,
    required this.inventoryLedgerAccountId,
    required this.cogsLedgerAccountId,
    required this.saleAt,
    this.accountsReceivableLedgerAccountId = 'ACC-AR',
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String baseCurrencyCode;
  final int exchangeRateScaled;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String salesRevenueAccountId;
  final String inventoryLedgerAccountId;
  final String cogsLedgerAccountId;
  final String accountsReceivableLedgerAccountId;
  final DateTime saleAt;
}

class ApprovedSaleDraftToCommand {
  const ApprovedSaleDraftToCommand();

  PostSaleCommand build({
    required OperationalDraft draft,
    required SalePostingContext context,
  }) {
    if (draft.commandName != 'CreateSaleDraft') {
      throw const DomainError(
        'SALE_DRAFT_COMMAND_INVALID',
        'Only CreateSaleDraft drafts can become PostSale commands.',
      );
    }
    draft.requireValidApprovalForPosting();

    final warehouseId = draft.payload['warehouse_id'];
    final currencyCode = draft.payload['currency_code'];
    final customerId = draft.payload['customer_id'];
    final settlementRaw = draft.payload['settlement_mode'] ?? 'cash';
    final linesValue = draft.payload['lines'];
    if (warehouseId is! String ||
        warehouseId.trim().isEmpty ||
        currencyCode is! String ||
        customerId is! String ||
        customerId.trim().isEmpty ||
        settlementRaw is! String ||
        linesValue is! List ||
        linesValue.isEmpty) {
      throw const DomainError(
        'SALE_DRAFT_PAYLOAD_INVALID',
        'Approved sale draft is missing posting fields.',
      );
    }

    final settlementMode = switch (settlementRaw.trim().toLowerCase()) {
      'cash' => SaleSettlementMode.cash,
      'credit' => SaleSettlementMode.credit,
      _ => throw const DomainError(
          'SALE_SETTLEMENT_MODE_INVALID',
          'Approved sale draft contains an unsupported settlement mode.',
        ),
    };

    final lines = <PostSaleLineInput>[];
    for (final raw in linesValue) {
      if (raw is! Map) {
        throw const DomainError(
          'SALE_DRAFT_LINE_INVALID',
          'Approved sale draft contains an invalid line.',
        );
      }
      final productId = raw['product_id'];
      final quantityScaled = raw['quantity_scaled'];
      final unitPriceScaled = raw['unit_price_scaled'];
      if (productId is! String ||
          productId.trim().isEmpty ||
          quantityScaled is! int ||
          quantityScaled <= 0 ||
          unitPriceScaled is! int ||
          unitPriceScaled <= 0) {
        throw const DomainError(
          'SALE_DRAFT_LINE_INVALID',
          'Approved sale draft contains invalid posting values.',
        );
      }
      lines.add(
        PostSaleLineInput(
          productId: productId,
          quantityScaled: quantityScaled,
          unitPriceScaled: unitPriceScaled,
        ),
      );
    }

    return PostSaleCommand(
      operationId: context.operationId,
      businessId: context.businessId,
      userId: context.userId,
      warehouseId: warehouseId,
      currencyCode: currencyCode,
      baseCurrencyCode: context.baseCurrencyCode,
      exchangeRateScaled: context.exchangeRateScaled,
      cashAccountId: context.cashAccountId,
      cashLedgerAccountId: context.cashLedgerAccountId,
      salesRevenueAccountId: context.salesRevenueAccountId,
      inventoryLedgerAccountId: context.inventoryLedgerAccountId,
      cogsLedgerAccountId: context.cogsLedgerAccountId,
      accountsReceivableLedgerAccountId: context.accountsReceivableLedgerAccountId,
      customerId: customerId,
      settlementMode: settlementMode,
      saleAt: context.saleAt,
      lines: List.unmodifiable(lines),
    );
  }
}
