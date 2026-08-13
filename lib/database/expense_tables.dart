import 'package:drift/drift.dart';

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get category => text()();
  TextColumn get description => text().nullable()();
  TextColumn get cashAccountId => text()();
  TextColumn get currencyCode => text()();
  TextColumn get baseCurrencyCode => text()();
  IntColumn get exchangeRateScaled => integer()();
  IntColumn get amountScaled => integer()();
  IntColumn get baseAmountScaled => integer()();
  TextColumn get journalEntryId => text()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  DateTimeColumn get expenseAt => dateTime()();
  TextColumn get operationId => text().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, documentNo},
      ];
}
