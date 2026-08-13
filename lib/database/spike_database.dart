import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'authorization_tables.dart';
import 'business_settings_table.dart';
import 'customer_receipts_table.dart';
import 'expense_reversal_tables.dart';
import 'expense_tables.dart';
import 'fx_rate_tables.dart';
import 'master_data_tables.dart';
import 'operational_drafts_table.dart';
import 'purchase_return_tables.dart';
import 'sale_return_tables.dart';
import 'spike_tables.dart';
import 'stock_transfer_tables.dart';
import 'supplier_payments_table.dart';

part 'spike_database.g.dart';

@DriftDatabase(
  tables: [
    DocumentSequences,
    OperationLog,
    InventoryBalances,
    Sales,
    SaleItems,
    Purchases,
    PurchaseItems,
    SaleReturns,
    SaleReturnItems,
    SaleRefundPayments,
    PurchaseReturns,
    PurchaseReturnItems,
    PurchaseReturnCashReceipts,
    StockMovements,
    StockMovementItems,
    StockTransfers,
    StockTransferItems,
    JournalEntries,
    JournalLines,
    Payments,
    PurchasePayments,
    CustomerLedger,
    SupplierLedger,
    CustomerReceipts,
    SupplierPayments,
    Expenses,
    ExpenseReversals,
    AuditLogs,
    OperationalDraftRecords,
    AppUsers,
    Roles,
    UserRoles,
    RolePermissions,
    FxRates,
    Customers,
    Suppliers,
    Products,
    Units,
    ProductUnits,
    Warehouses,
    BusinessSettings,
  ],
)
class SpikeDatabase extends _$SpikeDatabase {
  SpikeDatabase(QueryExecutor executor) : super(executor);

  factory SpikeDatabase.inMemory() => SpikeDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(sales, sales.baseCurrencyCode);
          if (from < 3) await m.createTable(operationalDraftRecords);
          if (from < 4) {
            await m.createTable(customers);
            await m.createTable(products);
            await m.createTable(units);
            await m.createTable(productUnits);
            await m.createTable(warehouses);
          }
          if (from < 5) {
            await m.addColumn(sales, sales.customerId);
            await m.addColumn(sales, sales.settlementMode);
            await m.createTable(customerLedger);
          }
          if (from < 6) await m.createTable(customerReceipts);
          if (from < 7) {
            await m.createTable(suppliers);
            await m.createTable(purchases);
            await m.createTable(purchaseItems);
            await m.createTable(purchasePayments);
            await m.createTable(supplierLedger);
          }
          if (from < 8) await m.createTable(supplierPayments);
          if (from < 9) {
            await m.createTable(stockTransfers);
            await m.createTable(stockTransferItems);
          }
          if (from < 10) {
            await m.createTable(saleReturns);
            await m.createTable(saleReturnItems);
            await m.createTable(saleRefundPayments);
          }
          if (from < 11) {
            await m.createTable(purchaseReturns);
            await m.createTable(purchaseReturnItems);
            await m.createTable(purchaseReturnCashReceipts);
          }
          if (from < 12) {
            await m.createTable(appUsers);
            await m.createTable(roles);
            await m.createTable(userRoles);
            await m.createTable(rolePermissions);
          }
          if (from < 13) await m.createTable(fxRates);
          if (from < 14) await m.createTable(expenses);
          if (from < 15) await m.createTable(expenseReversals);
          if (from < 16) await m.createTable(businessSettings);
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
