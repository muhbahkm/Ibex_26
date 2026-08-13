import '../core/errors/domain_error.dart';
import '../core/value_objects/money.dart';
import '../core/value_objects/quantity.dart';
import 'command_registry.dart';
import 'operational_draft.dart';

class CreatePurchaseDraftRequest {
  const CreatePurchaseDraftRequest({
    required this.draftId,
    required this.warehouseId,
    required this.productId,
    required this.quantityText,
    required this.quantityPrecision,
    required this.unitCostText,
    required this.currencyCode,
    required this.createdAtUtc,
    this.supplierId,
    this.settlementMode = 'cash',
  });

  final String draftId;
  final String warehouseId;
  final String? supplierId;
  final String productId;
  final String quantityText;
  final int quantityPrecision;
  final String unitCostText;
  final String currencyCode;
  final String settlementMode;
  final DateTime createdAtUtc;
}

class CreatePurchaseDraftService {
  const CreatePurchaseDraftService({required this.registry});

  static const commandName = 'CreatePurchaseDraft';

  final AgentCommandRegistry registry;

  OperationalDraft execute(CreatePurchaseDraftRequest request) {
    registry.requireRegistered(commandName);
    final draftId = request.draftId.trim();
    final warehouseId = request.warehouseId.trim();
    final productId = request.productId.trim();
    final supplierId = request.supplierId?.trim();
    final settlement = request.settlementMode.trim().toLowerCase();
    if (draftId.isEmpty || warehouseId.isEmpty || productId.isEmpty) {
      throw const DomainError(
        'PURCHASE_DRAFT_REQUIRED_FIELDS',
        'Purchase draft identity, warehouse and product are required.',
      );
    }
    if (settlement != 'cash' && settlement != 'credit') {
      throw const DomainError(
        'PURCHASE_SETTLEMENT_MODE_INVALID',
        'Purchase settlement mode must be cash or credit.',
      );
    }
    if (settlement == 'credit' && (supplierId == null || supplierId.isEmpty)) {
      throw const DomainError(
        'PURCHASE_CREDIT_SUPPLIER_REQUIRED',
        'Credit purchase draft requires a supplier.',
      );
    }

    final quantity = Quantity.parseExact(
      request.quantityText,
      allowedDecimals: request.quantityPrecision,
    );
    final unitCost = Money.parseExact(request.unitCostText, request.currencyCode);
    if (quantity.isZero || quantity.isNegative) {
      throw const DomainError(
        'PURCHASE_DRAFT_QUANTITY_INVALID',
        'Purchase draft quantity must be greater than zero.',
      );
    }
    if (unitCost.isZero || unitCost.isNegative) {
      throw const DomainError(
        'PURCHASE_DRAFT_COST_INVALID',
        'Purchase draft unit cost must be greater than zero.',
      );
    }

    return OperationalDraft(
      draftId: draftId,
      commandName: commandName,
      version: 1,
      payload: Map.unmodifiable({
        'warehouse_id': warehouseId,
        'supplier_id': supplierId,
        'settlement_mode': settlement,
        'currency_code': unitCost.currencyCode,
        'lines': [
          {
            'product_id': productId,
            'quantity_scaled': quantity.scaled,
            'quantity_precision': request.quantityPrecision,
            'unit_cost_scaled': unitCost.scaled,
          },
        ],
      }),
      state: OperationalDraftState.draftReady,
      createdAtUtc: request.createdAtUtc.toUtc(),
    ).markAwaitingApproval();
  }
}
