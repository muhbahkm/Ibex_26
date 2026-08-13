import '../core/errors/domain_error.dart';
import '../core/value_objects/money.dart';
import '../core/value_objects/quantity.dart';
import 'command_registry.dart';
import 'operational_draft.dart';

class SaleDraftCustomer {
  const SaleDraftCustomer({required this.id, required this.name});
  final String id;
  final String name;
}

class SaleDraftProduct {
  const SaleDraftProduct({required this.id, required this.name});
  final String id;
  final String name;
}

class SaleDraftUnit {
  const SaleDraftUnit({
    required this.id,
    required this.name,
    required this.quantityPrecision,
  });
  final String id;
  final String name;
  final int quantityPrecision;
}

abstract interface class SaleDraftCatalog {
  Future<List<SaleDraftCustomer>> findCustomers(String query);
  Future<List<SaleDraftProduct>> findProducts(String query);
  Future<List<SaleDraftUnit>> findUnitsForProduct(String productId, String query);
}

class CreateSaleDraftRequest {
  const CreateSaleDraftRequest({
    required this.draftId,
    required this.customerQuery,
    required this.productQuery,
    required this.unitQuery,
    required this.quantityText,
    required this.unitPriceText,
    required this.currencyCode,
    required this.warehouseId,
    required this.createdAtUtc,
    this.settlementMode = 'credit',
  });

  final String draftId;
  final String customerQuery;
  final String productQuery;
  final String unitQuery;
  final String quantityText;
  final String unitPriceText;
  final String currencyCode;
  final String warehouseId;
  final DateTime createdAtUtc;
  final String settlementMode;
}

class CreateSaleDraftService {
  const CreateSaleDraftService({
    required this.catalog,
    required this.registry,
  });

  static const commandName = 'CreateSaleDraft';

  final SaleDraftCatalog catalog;
  final AgentCommandRegistry registry;

  Future<OperationalDraft> execute(CreateSaleDraftRequest request) async {
    registry.requireRegistered(commandName);
    _requireNonBlank(request.draftId, 'DRAFT_ID_REQUIRED');
    _requireNonBlank(request.warehouseId, 'WAREHOUSE_REQUIRED');
    final settlementMode = request.settlementMode.trim().toLowerCase();
    if (settlementMode != 'cash' && settlementMode != 'credit') {
      throw const DomainError(
        'SALE_SETTLEMENT_MODE_INVALID',
        'Sale settlement mode must be cash or credit.',
      );
    }

    final customer = _resolveOne<SaleDraftCustomer>(
      await catalog.findCustomers(request.customerQuery.trim()),
      missingCode: 'CUSTOMER_NOT_FOUND',
      ambiguousCode: 'CUSTOMER_AMBIGUOUS',
    );
    final product = _resolveOne<SaleDraftProduct>(
      await catalog.findProducts(request.productQuery.trim()),
      missingCode: 'PRODUCT_NOT_FOUND',
      ambiguousCode: 'PRODUCT_AMBIGUOUS',
    );
    final unit = _resolveOne<SaleDraftUnit>(
      await catalog.findUnitsForProduct(product.id, request.unitQuery.trim()),
      missingCode: 'UNIT_NOT_FOUND',
      ambiguousCode: 'UNIT_AMBIGUOUS',
    );

    final quantity = Quantity.parseExact(
      request.quantityText,
      allowedDecimals: unit.quantityPrecision,
    );
    final unitPrice = Money.parseExact(
      request.unitPriceText,
      request.currencyCode,
    );

    if (quantity.isZero || quantity.isNegative) {
      throw const DomainError(
        'SALE_DRAFT_QUANTITY_INVALID',
        'Sale draft quantity must be greater than zero.',
      );
    }
    if (unitPrice.isZero || unitPrice.isNegative) {
      throw const DomainError(
        'SALE_DRAFT_PRICE_INVALID',
        'Sale draft unit price must be greater than zero.',
      );
    }

    final payload = <String, Object?>{
      'customer_id': customer.id,
      'customer_name': customer.name,
      'warehouse_id': request.warehouseId.trim(),
      'currency_code': unitPrice.currencyCode,
      'settlement_mode': settlementMode,
      'lines': [
        {
          'product_id': product.id,
          'product_name': product.name,
          'unit_id': unit.id,
          'unit_name': unit.name,
          'quantity_scaled': quantity.scaled,
          'quantity_precision': unit.quantityPrecision,
          'unit_price_scaled': unitPrice.scaled,
        },
      ],
    };

    return OperationalDraft(
      draftId: request.draftId.trim(),
      commandName: commandName,
      version: 1,
      payload: Map.unmodifiable(payload),
      state: OperationalDraftState.draftReady,
      createdAtUtc: request.createdAtUtc.toUtc(),
    ).markAwaitingApproval();
  }

  T _resolveOne<T>(
    List<T> matches, {
    required String missingCode,
    required String ambiguousCode,
  }) {
    if (matches.isEmpty) {
      throw DomainError(missingCode, 'No matching entity was found.');
    }
    if (matches.length != 1) {
      throw DomainError(ambiguousCode, 'The request matches more than one entity.');
    }
    return matches.single;
  }

  void _requireNonBlank(String value, String code) {
    if (value.trim().isEmpty) {
      throw DomainError(code, 'Required value is missing.');
    }
  }
}
