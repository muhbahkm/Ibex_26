import 'package:drift/drift.dart';

class OperationalDraftRecords extends Table {
  TextColumn get draftId => text()();
  TextColumn get commandName => text()();
  IntColumn get version => integer()();
  TextColumn get payloadJson => text()();
  TextColumn get state => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  TextColumn get approvedFingerprint => text().nullable()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {draftId};
}
