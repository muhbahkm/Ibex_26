import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_sale_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_sale_draft_service.dart';
import 'package:ibex_foundation_spike/agent/local_sale_draft_catalog.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/agent/sale_operational_workflow.dart';
import 'package:ibex_foundation_spike/core/text/arabic_search_normalizer.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';
import 'package:ibex_foundation_spike/presentation/persistent_sale_chat_controller.dart';
import 'package:ibex_foundation_spike/queries/customer_balance_query.dart';
import 'package:ibex_foundation_spike/queries/inventory_query.dart';
import 'package:ibex_foundation_spike/queries/local_supplier_lookup.dart';
import 'package:ibex_foundation_spike/queries/operational_read_query_service.dart';
import 'package:ibex_foundation_spike/queries/supplier_balance_query.dart';

void main() {
  late SpikeDatabase db;
  late PersistentSaleChatController controller;

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
            debitScaled: const Value(75 * 10000),
            baseDebitScaled: const Value(75 * 10000),
            occurredAt: now,
            operationId: 'OP-SALE-1',
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
            creditScaled: const Value(600 * 10000),
            baseCreditScaled: const Value(600 * 10000),
            occurredAt: now,
            operationId: 'OP-PUR-1',
          ),
        );
    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            warehouseId: 'WH-1',
            productId: 'P-1',
            quantityScaled: 9 * 1000000,
            inventoryValueScaled: 450 * 10000,
            wacUnitCostScaled: 50 * 10000,
            updatedAt: now,
          ),
        );

    final catalog = LocalSaleDraftCatalog(db: db, businessId: 'B-1');
    final workflow = SaleOperationalWorkflow(
      createSaleDraft: CreateSaleDraftService(
        catalog: catalog,
        registry: const AgentCommandRegistry({CreateSaleDraftService.commandName}),
      ),
      draftRepository: OperationalDraftRepository(db),
      postSaleService: PostSaleService(db),
    );
    controller = PersistentSaleChatController(
      workflow: workflow,
      defaultWarehouseId: 'WH-1',
      readQueries: OperationalReadQueryService(
        catalog: catalog,
        customerBalances: CustomerBalanceQuery(db),
        inventory: InventoryQuery(db),
        supplierLookup: LocalSupplierLookup(db: db, businessId: 'B-1'),
        supplierBalances: SupplierBalanceQuery(db),
        businessId: 'B-1',
        defaultWarehouseId: 'WH-1',
      ),
      postingContextFactory: (OperationalDraft draft) => SalePostingContext(
        operationId: 'unused-read-only-operation',
        businessId: 'B-1',
        userId: 'U-1',
        baseCurrencyCode: 'YER',
        exchangeRateScaled: 100000000,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        salesRevenueAccountId: 'ACC-SALES',
        inventoryLedgerAccountId: 'ACC-INV',
        cogsLedgerAccountId: 'ACC-COGS',
        accountsReceivableLedgerAccountId: 'ACC-AR',
        saleAt: now,
      ),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('customer balance chat reads ledger truth without creating operational writes', () async {
    controller.submitNaturalLanguage('كم رصيد محمد عبدالله؟');
    await _waitForController(controller);

    expect(controller.lastError, isNull);
    expect(controller.messages.last.text, contains('75 YER'));
    expect(controller.draft, isNull);
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.stockMovements).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('supplier balance chat reads payable truth without creating payment or journal', () async {
    controller.submitNaturalLanguage('كم رصيد المورد مورد العسل؟');
    await _waitForController(controller);

    expect(controller.lastError, isNull);
    expect(controller.messages.last.text, contains('600 SAR'));
    expect(controller.draft, isNull);
    expect(await db.select(db.supplierPayments).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
    expect(await db.select(db.auditLogs).get(), isEmpty);
  });

  test('inventory chat reads local stock without mutating inventory or opening a draft', () async {
    controller.submitNaturalLanguage('اعرض مخزون السدر عبوة كيلو');
    await _waitForController(controller);

    expect(controller.lastError, isNull);
    expect(controller.messages.last.text, contains('9 وحدة أساسية'));
    expect(controller.draft, isNull);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 9 * 1000000);
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.auditLogs).get(), isEmpty);
  });
}

Future<void> _waitForController(PersistentSaleChatController controller) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (!controller.busy) return;
  }
  fail('Persistent controller did not become idle.');
}
