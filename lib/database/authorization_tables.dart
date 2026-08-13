import 'package:drift/drift.dart';

class AppUsers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get displayName => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Roles extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get name => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class UserRoles extends Table {
  TextColumn get businessId => text()();
  TextColumn get userId => text().references(AppUsers, #id)();
  TextColumn get roleId => text().references(Roles, #id)();

  @override
  Set<Column<Object>> get primaryKey => {businessId, userId, roleId};
}

class RolePermissions extends Table {
  TextColumn get businessId => text()();
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get permission => text()();

  @override
  Set<Column<Object>> get primaryKey => {businessId, roleId, permission};
}
