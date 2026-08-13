import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/local_sale_draft_catalog.dart';
import 'package:ibex_foundation_spike/core/text/arabic_search_normalizer.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/queries/customer_balance_query.dart';
import 'package:ibex_foundation_spike/queries/inventory_query.dart';
import 'package:ibex_foundation_spike/queries/local_supplier_lookup.dart';
import 'package:ibex_foundation_spike/queries/operational_read_query_service.dart';
import 'package:ibex_foundation_spike/queries/supplier_balance_query.dart';

void main() {
  late SpikeDatabase db;
  late OperationalReadQueryService reads;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    final now = DateTime.utc(2026, 8, 11);
    await db.into(db.customers).insert(
          CustomersCompanion.insert(
            id: 'C-1',
            businessId: 'B-1',
            name: 'محمد عبدالله باحكم',
            normalizedName: ArabicSearchNormalizer.normalize('محمد عبدالله باحكم'),
            updatedAt: now,
          ),
        );
    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            id: 'SUP-1',
            businessId: 'B-1',
            name: 'مورد العسل',
            normalizedName: ArabicSearchNormalizer.normalize('مورد العسل'),
            updatedAt: now,
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'P-1',
            businessId: 'B-1',
            name: 'سدر — عبوة كيلو',
            normalizedName: ArabicSearchNormalizer.normalize('سدر عبوة كيلو'),
            updatedAt: now,
          ),
        );
    await db.into(db.customerLedger).insert(
          CustomerLedgerCompanion.insert(
            id: 'L-1',
            businessId: 'B-1',
            customerId: 'C-1',
            sourceType: 'sale',
            sourceId: 'SALE-1',
            currencyCode: 'YER',
            debitScaled: const Value(120 * 10000),
            baseDebitScaled: const Value(120 * 10000),
            occurredAt: now,
            operationId: 'OP-SALE-1',
          ),
        );
    await db.into(db.customerLedger).insert(
          CustomerLedgerCompanion.insert(
            id: 'L-2',
            businessId: 'B-1',
            customerId: 'C-1',
            sourceType: 'customer_receipt',
            sourceId: 'RCT-1',
            currencyCode: 'YER',
            creditScaled: const Value(20 * 10000),
            baseCreditScaled: const Value(20 * 10000),
            occurredAt: now,
            operationId: 'OP-RCT-1',
          ),
        );
    await db.into(db.supplierLedger).insert(
          SupplierLedgerCompanion.insert(
            id: 'SL-1',
            businessId: 'B-1',
            supplierId: 'SUP-1',
            sourceType: 'purchase',
            sourceId: 'PUR-1',
            currencyCode: 'SAR',
            creditScaled: const Value(900 * 10000),
            baseCreditScaled: const Value(900 * 10000),
            occurredAt: now,
            operationId: 'OP-PUR-1',
          ),
        );
    await db.into(db.supplierLedger).insert(
          SupplierLedgerCompanion.insert(
            id: 'SL-2',
            businessId: 'B-1',
            supplierId: 'SUP-1',
            sourceType: 'supplier_payment',
            sourceId: 'PAY-1',
            currencyCode: 'SAR',
            debitScaled: const Value(300 * 10000),
            baseDebitScaled: const Value(300 * 10000),
            occurredAt: now,
            operationId: 'OP-PAY-1',
          ),
        );
    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            warehouseId: 'WH-1',
            productId: 'P-1',
            quantityScaled: 7 * 1000000,
            inventoryValueScaled: 350 * 10000,
            wacUnitCostScaled: 50 * 10000,
            updatedAt: now,
          ),
        );

    final catalog = LocalSaleDraftCatalog(db: db, businessId: 'B-1');
    reads = OperationalReadQueryService(
      catalog: catalog,
      customerBalances: CustomerBalanceQuery(db),
      inventory: InventoryQuery(db),
      supplierLookup: LocalSupplierLookup(db: db, businessId: 'B-1'),
      supplierBalances: SupplierBalanceQuery(db),
      businessId: 'B-1',
      defaultWarehouseId: 'WH-1',
    );
  });

  tearDown(() => db.close());

  test('customer balance resolves local customer and returns ledger truth', () async {
    final result = await reads.customerBalance('محمد عبدالله');
    expect(result.customerId, 'C-1');
    expect(result.customerName, 'محمد عبدالله باحكم');
    expect(result.balances, hasLength(1));
    expect(result.balances.single.currencyCode, 'YER');
    expect(result.balances.single.balanceScaled, 100 * 10000);
  });

  test('supplier balance resolves local supplier and returns payable truth', () async {
    final result = await reads.supplierBalance('مورد العسل');
    expect(result.supplierId, 'SUP-1');
    expect(result.supplierName, 'مورد العسل');
    expect(result.balances, hasLength(1));
    expect(result.balances.single.currencyCode, 'SAR');
    expect(result.balances.single.balanceScaled, 600 * 10000);
  });

  test('inventory balance resolves local product and returns warehouse truth', () async {
    final result = await reads.inventoryBalance('سدر عبوة كيلو');
    expect(result.productId, 'P-1');
    expect(result.balance, isNotNull);
    expect(result.balance!.quantityScaled, 7 * 1000000);
    expect(result.balance!.wacUnitCostScaled, 50 * 10000);
  });
}
