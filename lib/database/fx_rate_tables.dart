import 'package:drift/drift.dart';

class FxRates extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get fromCurrency => text()();
  TextColumn get toCurrency => text()();
  IntColumn get rateScaled => integer()();
  DateTimeColumn get effectiveAt => dateTime()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get sourceNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, fromCurrency, toCurrency, effectiveAt},
      ];
}
