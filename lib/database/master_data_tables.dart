import 'package:drift/drift.dart';

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, sku},
      ];
}

class Units extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  IntColumn get quantityPrecision => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProductUnits extends Table {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  IntColumn get conversionFactorScaled => integer().withDefault(const Constant(1000000))();
  BoolColumn get isBase => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {productId, unitId};
}

class Warehouses extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}