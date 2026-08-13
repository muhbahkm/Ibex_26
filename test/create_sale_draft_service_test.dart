import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_sale_draft_service.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';

class _Catalog implements SaleDraftCatalog {
  _Catalog({
    this.customers = const [SaleDraftCustomer(id: 'customer-1', name: 'محمد عبدالله باحكم')],
    this.products = const [SaleDraftProduct(id: 'product-1', name: 'سدر — عبوة كيلو')],
    this.units = const [SaleDraftUnit(id: 'unit-1', name: 'جالون', quantityPrecision: 0)],
  });

  final List<SaleDraftCustomer> customers;
  final List<SaleDraftProduct> products;
  final List<SaleDraftUnit> units;

  @override
  Future<List<SaleDraftCustomer>> findCustomers(String query) async => customers;

  @override
  Future<List<SaleDraftProduct>> findProducts(String query) async => products;

  @override
  Future<List<SaleDraftUnit>> findUnitsForProduct(String productId, String query) async => units;
}

CreateSaleDraftRequest _request() => CreateSaleDraftRequest(
      draftId: 'draft-sale-1',
      customerQuery: 'محمد عبدالله باحكم',
      productQuery: 'سدر عبوة كيلو',
      unitQuery: 'جالون',
      quantityText: '1',
      unitPriceText: '500',
      currencyCode: 'SAR',
      warehouseId: 'warehouse-main',
      createdAtUtc: DateTime.utc(2026, 8, 11, 10),
    );

void main() {
  const registry = AgentCommandRegistry({CreateSaleDraftService.commandName});

  test('CreateSaleDraft resolves one customer/product/unit into an awaiting approval draft', () async {
    final service = CreateSaleDraftService(catalog: _Catalog(), registry: registry);
    final draft = await service.execute(_request());

    expect(draft.commandName, CreateSaleDraftService.commandName);
    expect(draft.version, 1);
    expect(draft.state, OperationalDraftState.awaitingApproval);
    expect(draft.approvedFingerprint, isNull);
    expect(draft.payload['customer_id'], 'customer-1');
    expect(draft.payload['customer_name'], 'محمد عبدالله باحكم');
    expect(draft.payload['currency_code'], 'SAR');

    final lines = draft.payload['lines']! as List<Object?>;
    final line = lines.single! as Map<String, Object?>;
    expect(line['product_id'], 'product-1');
    expect(line['unit_id'], 'unit-1');
    expect(line['quantity_scaled'], 1000000);
    expect(line['unit_price_scaled'], 5000000);
  });

  test('CreateSaleDraft refuses ambiguous customer instead of guessing', () async {
    final service = CreateSaleDraftService(
      catalog: _Catalog(
        customers: const [
          SaleDraftCustomer(id: 'customer-1', name: 'محمد عبدالله باحكم'),
          SaleDraftCustomer(id: 'customer-2', name: 'محمد باحكم'),
        ],
      ),
      registry: registry,
    );

    await expectLater(
      service.execute(_request()),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'CUSTOMER_AMBIGUOUS'),
      ),
    );
  });

  test('CreateSaleDraft refuses ambiguous product instead of guessing', () async {
    final service = CreateSaleDraftService(
      catalog: _Catalog(
        products: const [
          SaleDraftProduct(id: 'product-1', name: 'سدر — عبوة كيلو'),
          SaleDraftProduct(id: 'product-2', name: 'سدر فاخر — عبوة كيلو'),
        ],
      ),
      registry: registry,
    );

    await expectLater(
      service.execute(_request()),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'PRODUCT_AMBIGUOUS'),
      ),
    );
  });

  test('CreateSaleDraft refuses a unit that is not resolved for the selected product', () async {
    final service = CreateSaleDraftService(
      catalog: _Catalog(units: const []),
      registry: registry,
    );

    await expectLater(
      service.execute(_request()),
      throwsA(isA<DomainError>().having((error) => error.code, 'code', 'UNIT_NOT_FOUND')),
    );
  });

  test('CreateSaleDraft validates positive exact quantity and price before preview', () async {
    final service = CreateSaleDraftService(catalog: _Catalog(), registry: registry);

    final invalidQuantity = CreateSaleDraftRequest(
      draftId: _request().draftId,
      customerQuery: _request().customerQuery,
      productQuery: _request().productQuery,
      unitQuery: _request().unitQuery,
      quantityText: '0',
      unitPriceText: '500',
      currencyCode: 'SAR',
      warehouseId: _request().warehouseId,
      createdAtUtc: _request().createdAtUtc,
    );

    await expectLater(
      service.execute(invalidQuantity),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'SALE_DRAFT_QUANTITY_INVALID'),
      ),
    );
  });
}
