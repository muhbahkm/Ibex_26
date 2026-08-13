import '../core/errors/domain_error.dart';
import '../operating_engine/transfer_stock_command.dart';
import 'create_stock_transfer_draft_service.dart';
import 'operational_draft.dart';

class StockTransferPostingContext {
  const StockTransferPostingContext({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.transferredAt,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final DateTime transferredAt;
}

class ApprovedStockTransferDraftToCommand {
  const ApprovedStockTransferDraftToCommand();

  TransferStockCommand build({
    required OperationalDraft draft,
    required StockTransferPostingContext context,
  }) {
    if (draft.commandName != CreateStockTransferDraftService.commandName) {
      throw const DomainError(
        'STOCK_TRANSFER_DRAFT_COMMAND_INVALID',
        'Only CreateStockTransferDraft drafts can become TransferStock commands.',
      );
    }
    draft.requireValidApprovalForPosting();

    final source = draft.payload['source_warehouse_id'];
    final destination = draft.payload['destination_warehouse_id'];
    final linesRaw = draft.payload['lines'];
    if (source is! String ||
        source.trim().isEmpty ||
        destination is! String ||
        destination.trim().isEmpty ||
        source == destination ||
        linesRaw is! List ||
        linesRaw.isEmpty) {
      throw const DomainError(
        'STOCK_TRANSFER_DRAFT_PAYLOAD_INVALID',
        'Approved transfer draft is missing or contains invalid posting fields.',
      );
    }

    final lines = <TransferStockLineInput>[];
    for (final raw in linesRaw) {
      if (raw is! Map) {
        throw const DomainError(
          'STOCK_TRANSFER_DRAFT_LINE_INVALID',
          'Approved transfer draft contains an invalid line.',
        );
      }
      final productId = raw['product_id'];
      final quantityScaled = raw['quantity_scaled'];
      if (productId is! String ||
          productId.trim().isEmpty ||
          quantityScaled is! int ||
          quantityScaled <= 0) {
        throw const DomainError(
          'STOCK_TRANSFER_DRAFT_LINE_INVALID',
          'Approved transfer draft contains invalid posting values.',
        );
      }
      lines.add(
        TransferStockLineInput(
          productId: productId,
          quantityScaled: quantityScaled,
        ),
      );
    }

    return TransferStockCommand(
      operationId: context.operationId,
      businessId: context.businessId,
      userId: context.userId,
      sourceWarehouseId: source,
      destinationWarehouseId: destination,
      transferredAt: context.transferredAt,
      lines: List.unmodifiable(lines),
    );
  }
}
