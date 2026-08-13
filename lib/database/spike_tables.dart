import 'package:drift/drift.dart';

class DocumentSequences extends Table {
  TextColumn get businessId => text()();
  TextColumn get documentType => text()();
  TextColumn get scopeKey => text()();
  TextColumn get prefix => text()();
  IntColumn get nextValue => integer()();
  IntColumn get padding => integer().withDefault(const Constant(6))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {businessId, documentType, scopeKey};
}

class OperationLog extends Table {
  TextColumn get operationId => text()();
  TextColumn get businessId => text()();
  TextColumn get commandName => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class InventoryBalances extends Table {
  TextColumn get warehouseId => text()();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get inventoryValueScaled => integer()();
  IntColumn get wacUnitCostScaled => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {warehouseId, productId};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get warehouseId => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get settlementMode => text().withDefault(const Constant('cash'))();
  TextColumn get currencyCode => text()();
  TextColumn get baseCurrencyCode => text().nullable()();
  IntColumn get exchangeRateScaled => integer()();
  IntColumn get totalScaled => integer()();
  IntColumn get baseTotalScaled => integer()();
  TextColumn get status => text()();
  DateTimeColumn get saleAt => dateTime()();
  TextColumn get journalEntryId => text()();
  TextColumn get stockMovementId => text()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, documentNo},
        {operationId},
      ];
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get baseQuantityScaled => integer()();
  IntColumn get unitPriceScaled => integer()();
  IntColumn get netScaled => integer()();
  IntColumn get cogsUnitCostScaled => integer()();
  IntColumn get cogsTotalScaled => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get warehouseId => text()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get settlementMode => text().withDefault(const Constant('cash'))();
  TextColumn get currencyCode => text()();
  TextColumn get baseCurrencyCode => text()();
  IntColumn get exchangeRateScaled => integer()();
  IntColumn get totalScaled => integer()();
  IntColumn get baseTotalScaled => integer()();
  TextColumn get status => text()();
  DateTimeColumn get purchaseAt => dateTime()();
  TextColumn get journalEntryId => text()();
  TextColumn get stockMovementId => text()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, documentNo},
        {operationId},
      ];
}

class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get unitCostScaled => integer()();
  IntColumn get netScaled => integer()();
  IntColumn get baseNetScaled => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get warehouseId => text()();
  TextColumn get movementType => text()();
  TextColumn get referenceType => text()();
  TextColumn get referenceId => text()();
  TextColumn get status => text()();
  DateTimeColumn get movementAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class StockMovementItems extends Table {
  TextColumn get id => text()();
  TextColumn get stockMovementId => text().references(StockMovements, #id)();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get unitCostScaled => integer()();
  IntColumn get totalCostScaled => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class JournalEntries extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get status => text()();
  DateTimeColumn get entryAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class JournalLines extends Table {
  TextColumn get id => text()();
  TextColumn get journalEntryId => text().references(JournalEntries, #id)();
  TextColumn get accountId => text()();
  IntColumn get baseDebitScaled => integer().withDefault(const Constant(0))();
  IntColumn get baseCreditScaled => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get cashAccountId => text()();
  TextColumn get currencyCode => text()();
  IntColumn get amountScaled => integer()();
  IntColumn get baseAmountScaled => integer()();
  DateTimeColumn get paymentAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PurchasePayments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get cashAccountId => text()();
  TextColumn get currencyCode => text()();
  IntColumn get amountScaled => integer()();
  IntColumn get baseAmountScaled => integer()();
  DateTimeColumn get paymentAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {operationId},
      ];
}

class CustomerLedger extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get customerId => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get currencyCode => text()();
  IntColumn get debitScaled => integer().withDefault(const Constant(0))();
  IntColumn get creditScaled => integer().withDefault(const Constant(0))();
  IntColumn get baseDebitScaled => integer().withDefault(const Constant(0))();
  IntColumn get baseCreditScaled => integer().withDefault(const Constant(0))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {operationId, sourceType},
      ];
}

class SupplierLedger extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get supplierId => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get currencyCode => text()();
  IntColumn get debitScaled => integer().withDefault(const Constant(0))();
  IntColumn get creditScaled => integer().withDefault(const Constant(0))();
  IntColumn get baseDebitScaled => integer().withDefault(const Constant(0))();
  IntColumn get baseCreditScaled => integer().withDefault(const Constant(0))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {operationId, sourceType},
      ];
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get operationId => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get metadataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}