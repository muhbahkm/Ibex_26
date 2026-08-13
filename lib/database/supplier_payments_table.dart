import 'package:drift/drift.dart';

class SupplierPayments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get supplierId => text()();
  TextColumn get cashAccountId => text()();
  TextColumn get currencyCode => text()();
  TextColumn get baseCurrencyCode => text()();
  IntColumn get exchangeRateScaled => integer()();
  IntColumn get amountScaled => integer()();
  IntColumn get baseAmountScaled => integer()();
  TextColumn get journalEntryId => text()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get operationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, documentNo},
        {operationId},
      ];
}
