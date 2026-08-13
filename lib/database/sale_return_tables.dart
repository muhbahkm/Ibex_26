import 'package:drift/drift.dart';

import 'spike_tables.dart';

class SaleReturns extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get sourceSaleId => text().references(Sales, #id)();
  TextColumn get warehouseId => text()();
  TextColumn get customerId => text().nullable()();
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

class SaleReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleReturnId => text().references(SaleReturns, #id)();
  TextColumn get sourceSaleItemId => text().references(SaleItems, #id)();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get unitPriceScaled => integer()();
  IntColumn get refundScaled => integer()();
  IntColumn get cogsUnitCostScaled => integer()();
  IntColumn get cogsTotalScaled => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SaleRefundPayments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get saleReturnId => text().references(SaleReturns, #id)();
  TextColumn get cashAccountId => text()();
  TextColumn get currencyCode => text()();
  IntColumn get amountScaled => integer()();
  IntColumn get baseAmountScaled => integer()();
  DateTimeColumn get refundedAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {operationId},
      ];
}
