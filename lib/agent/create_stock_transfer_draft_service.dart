import '../core/errors/domain_error.dart';
import '../core/value_objects/quantity.dart';
import 'command_registry.dart';
import 'operational_draft.dart';

class CreateStockTransferDraftRequest {
  const CreateStockTransferDraftRequest({
    required this.draftId,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.productId,
    required this.quantityText,
    required this.quantityPrecision,
    required this.createdAtUtc,
  });

  final String draftId;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String productId;
  final String quantityText;
  final int quantityPrecision;
  final DateTime createdAtUtc;
}

class CreateStockTransferDraftService {
  const CreateStockTransferDraftService({required this.registry});

  static const commandName = 'CreateStockTransferDraft';

  final AgentCommandRegistry registry;

  OperationalDraft execute(CreateStockTransferDraftRequest request) {
    registry.requireRegistered(commandName);
    final draftId = request.draftId.trim();
    final source = request.sourceWarehouseId.trim();
    final destination = request.destinationWarehouseId.trim();
    final productId = request.productId.trim();
    if (draftId.isEmpty || source.isEmpty || destination.isEmpty || productId.isEmpty) {
      throw const DomainError(
        'STOCK_TRANSFER_DRAFT_REQUIRED_FIELDS',
        'Transfer draft identity, warehouses and product are required.',
      );
    }
    if (source == destination) {
      throw const DomainError(
        'STOCK_TRANSFER_SAME_WAREHOUSE',
        'Source and destination warehouses must differ.',
      );
    }

    final quantity = Quantity.parseExact(
      request.quantityText,
      allowedDecimals: request.quantityPrecision,
    );
    if (quantity.isZero || quantity.isNegative) {
      throw const DomainError(
        'STOCK_TRANSFER_DRAFT_QUANTITY_INVALID',
        'Transfer quantity must be greater than zero.',
      );
    }

    return OperationalDraft(
      draftId: draftId,
      commandName: commandName,
      version: 1,
      payload: Map.unmodifiable({
        'source_warehouse_id': source,
        'destination_warehouse_id': destination,
        'lines': [
          {
            'product_id': productId,
            'quantity_scaled': quantity.scaled,
            'quantity_precision': request.quantityPrecision,
          },
        ],
      }),
      state: OperationalDraftState.draftReady,
      createdAtUtc: request.createdAtUtc.toUtc(),
    ).markAwaitingApproval();
  }
}
