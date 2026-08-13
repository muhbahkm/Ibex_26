import 'package:drift/drift.dart';

import 'spike_tables.dart';

class PurchaseReturns extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get sourcePurchaseId => text().references(Purchases, #id)();
  TextColumn get warehouseId => text()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get settlementMode => text()();
  TextColumn get currencyCode => text()();
  TextColumn get baseCurrencyCode => text()();
  IntColumn get exchangeRateScaled => integer()();
  IntColumn get totalScaled => integer()();
  IntColumn get baseTotalScaled => integer()();
  TextColumn get status => text()();
  DateTimeColumn get returnedAt => dateTime()();
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

class PurchaseReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseReturnId => text().references(PurchaseReturns, #id)();
  TextColumn get sourcePurchaseItemId => text().references(PurchaseItems, #id)();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get unitCostScaled => integer()();
  IntColumn get returnScaled => integer()();
  IntColumn get baseReturnScaled => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PurchaseReturnCashReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get purchaseReturnId => text().references(PurchaseReturns, #id)();
  TextColumn get cashAccountId => text()();
  TextColumn get currencyCode => text()();
  IntColumn get amountScaled => integer()();
  IntColumn get baseAmountScaled => integer()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [{operationId}];
}
