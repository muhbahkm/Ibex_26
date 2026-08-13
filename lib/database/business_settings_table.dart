import 'package:drift/drift.dart';

class BusinessSettings extends Table {
  TextColumn get businessId => text()();
  TextColumn get displayName => text()();
  TextColumn get baseCurrencyCode => text()();
  IntColumn get utcOffsetMinutes => integer()();
  BoolColumn get onboardingComplete => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {businessId};
}
