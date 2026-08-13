import 'package:drift/drift.dart';

class StockTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get sourceWarehouseId => text()();
  TextColumn get destinationWarehouseId => text()();
  TextColumn get status => text()();
  DateTimeColumn get transferredAt => dateTime()();
  TextColumn get sourceMovementId => text()();
  TextColumn get destinationMovementId => text()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, documentNo},
        {operationId},
      ];
}

class StockTransferItems extends Table {
  TextColumn get id => text()();
  TextColumn get transferId => text().references(StockTransfers, #id)();
  TextColumn get productId => text()();
  IntColumn get quantityScaled => integer()();
  IntColumn get unitCostScaled => integer()();
  IntColumn get totalCostScaled => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
