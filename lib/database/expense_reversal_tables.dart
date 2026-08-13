import 'package:drift/drift.dart';

import 'expense_tables.dart';

class ExpenseReversals extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get documentNo => text()();
  TextColumn get sourceExpenseId => text().references(Expenses, #id)();
  TextColumn get reason => text()();
  TextColumn get journalEntryId => text()();
  DateTimeColumn get reversedAt => dateTime()();
  TextColumn get operationId => text().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {businessId, documentNo},
        {sourceExpenseId},
      ];
}
