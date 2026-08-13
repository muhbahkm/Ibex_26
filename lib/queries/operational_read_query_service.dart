import '../agent/create_sale_draft_service.dart';
import '../core/errors/domain_error.dart';
import 'customer_balance_query.dart';
import 'inventory_query.dart';
import 'local_supplier_lookup.dart';
import 'supplier_balance_query.dart';

class CustomerBalanceReadResult {
  const CustomerBalanceReadResult({
    required this.customerId,
    required this.customerName,
    required this.balances,
  });

  final String customerId;
  final String customerName;
  final List<CustomerCurrencyBalance> balances;
}

class SupplierBalanceReadResult {
  const SupplierBalanceReadResult({
    required this.supplierId,
    required this.supplierName,
    required this.balances,
  });

  final String supplierId;
  final String supplierName;
  final List<SupplierCurrencyBalance> balances;
}

class InventoryBalanceReadResult {
  const InventoryBalanceReadResult({
    required this.productId,
    required this.productName,
    required this.warehouseId,
    required this.balance,
  });

  final String productId;
  final String productName;
  final String warehouseId;
  final InventoryBalanceSnapshot? balance;
}

class OperationalReadQueryService {
  const OperationalReadQueryService({
    required this.catalog,
    required this.customerBalances,
    required this.inventory,
    required this.businessId,
    required this.defaultWarehouseId,
    this.supplierLookup,
    this.supplierBalances,
  });

  final SaleDraftCatalog catalog;
  final CustomerBalanceQuery customerBalances;
  final InventoryQuery inventory;
  final String businessId;
  final String defaultWarehouseId;
  final LocalSupplierLookup? supplierLookup;
  final SupplierBalanceQuery? supplierBalances;

  Future<CustomerBalanceReadResult> customerBalance(String customerQuery) async {
    final customer = _requireSingle(
      await catalog.findCustomers(customerQuery.trim()),
      missingCode: 'CUSTOMER_NOT_FOUND',
      ambiguousCode: 'CUSTOMER_AMBIGUOUS',
    );
    final balances = await customerBalances.execute(
      businessId: businessId,
      customerId: customer.id,
    );
    return CustomerBalanceReadResult(
      customerId: customer.id,
      customerName: customer.name,
      balances: List.unmodifiable(balances),
    );
  }

  Future<SupplierBalanceReadResult> supplierBalance(String supplierQuery) async {
    final lookup = supplierLookup;
    final balancesQuery = supplierBalances;
    if (lookup == null || balancesQuery == null) {
      throw const DomainError(
        'SUPPLIER_READ_SERVICE_UNAVAILABLE',
        'Supplier read dependencies are not configured.',
      );
    }
    final supplier = _requireSingle(
      await lookup.find(supplierQuery.trim()),
      missingCode: 'SUPPLIER_NOT_FOUND',
      ambiguousCode: 'SUPPLIER_AMBIGUOUS',
    );
    final balances = await balancesQuery.bySupplier(
      businessId: businessId,
      supplierId: supplier.id,
    );
    return SupplierBalanceReadResult(
      supplierId: supplier.id,
      supplierName: supplier.name,
      balances: List.unmodifiable(balances),
    );
  }

  Future<InventoryBalanceReadResult> inventoryBalance(String productQuery) async {
    final product = _requireSingle(
      await catalog.findProducts(productQuery.trim()),
      missingCode: 'PRODUCT_NOT_FOUND',
      ambiguousCode: 'PRODUCT_AMBIGUOUS',
    );
    final balance = await inventory.byProductWarehouse(
      productId: product.id,
      warehouseId: defaultWarehouseId,
    );
    return InventoryBalanceReadResult(
      productId: product.id,
      productName: product.name,
      warehouseId: defaultWarehouseId,
      balance: balance,
    );
  }

  T _requireSingle<T>(
    List<T> matches, {
    required String missingCode,
    required String ambiguousCode,
  }) {
    if (matches.isEmpty) {
      throw DomainError(missingCode, 'No matching local entity was found.');
    }
    if (matches.length != 1) {
      throw DomainError(ambiguousCode, 'The local query matches more than one entity.');
    }
    return matches.single;
  }
}
