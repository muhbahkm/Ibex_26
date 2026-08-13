import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/encrypted_database_opener.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ibex_migration_gate_');
    dbFile = File('${tempDir.path}${Platform.pathSeparator}ibex_v1.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('encrypted v1 database migrates through v16 without inventing historical truth', () async {
    _createEncryptedV1Snapshot(dbFile, key);

    final beforeHeader = await dbFile.openRead(0, 16).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    expect(beforeHeader, isNot(equals('SQLite format 3\u0000'.codeUnits)));

    final migrated = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: key),
    );

    final sale = await migrated.select(migrated.sales).getSingle();
    expect(sale.id, 'SALE-V1');
    expect(sale.documentNo, 'SAL-2026-000001');
    expect(sale.currencyCode, 'USD');
    expect(sale.baseCurrencyCode, isNull);
    expect(sale.customerId, isNull);
    expect(sale.settlementMode, 'cash');
    expect(sale.exchangeRateScaled, 375000000);
    expect(sale.totalScaled, 100 * 10000);
    expect(sale.baseTotalScaled, 375 * 10000);

    final version = await migrated.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 16);

    final columns = await migrated.customSelect('PRAGMA table_info(sales)').get();
    final columnNames = columns.map((row) => row.data['name']).toSet();
    expect(columnNames, containsAll(['base_currency_code', 'customer_id', 'settlement_mode']));

    final requiredTables = {
      'operational_draft_records',
      'customers',
      'suppliers',
      'products',
      'units',
      'product_units',
      'warehouses',
      'customer_ledger',
      'customer_receipts',
      'purchases',
      'purchase_items',
      'purchase_payments',
      'supplier_ledger',
      'supplier_payments',
      'stock_transfers',
      'stock_transfer_items',
      'sale_returns',
      'sale_return_items',
      'sale_refund_payments',
      'purchase_returns',
      'purchase_return_items',
      'purchase_return_cash_receipts',
      'app_users',
      'roles',
      'user_roles',
      'role_permissions',
      'fx_rates',
      'expenses',
      'expense_reversals',
      'business_settings',
    };
    final migratedTables = await migrated.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    final names = migratedTables.map((row) => row.read<String>('name')).toSet();
    expect(names.containsAll(requiredTables), isTrue);

    await migrated.close();

    final reopened = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: key),
    );
    final reopenedSale = await reopened.select(reopened.sales).getSingle();
    expect(reopenedSale.baseCurrencyCode, isNull);
    expect(reopenedSale.customerId, isNull);
    expect(reopenedSale.settlementMode, 'cash');
    expect(reopenedSale.operationId, 'OP-V1');
    await reopened.close();
  });
}

void _createEncryptedV1Snapshot(File file, String key) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    raw.execute("PRAGMA hexkey = '$key';");
    raw.select('SELECT count(*) FROM sqlite_master;');
    raw.execute('''
      CREATE TABLE sales (
        id TEXT NOT NULL PRIMARY KEY,
        business_id TEXT NOT NULL,
        document_no TEXT NOT NULL,
        warehouse_id TEXT NOT NULL,
        currency_code TEXT NOT NULL,
        exchange_rate_scaled INTEGER NOT NULL,
        total_scaled INTEGER NOT NULL,
        base_total_scaled INTEGER NOT NULL,
        status TEXT NOT NULL,
        sale_at INTEGER NOT NULL,
        journal_entry_id TEXT NOT NULL,
        stock_movement_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        UNIQUE (business_id, document_no),
        UNIQUE (operation_id)
      );
    ''');
    raw.execute('''
      INSERT INTO sales (
        id, business_id, document_no, warehouse_id, currency_code,
        exchange_rate_scaled, total_scaled, base_total_scaled, status,
        sale_at, journal_entry_id, stock_movement_id, operation_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      'SALE-V1',
      'B-1',
      'SAL-2026-000001',
      'WH-1',
      'USD',
      375000000,
      100 * 10000,
      375 * 10000,
      'posted',
      DateTime.utc(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
      'JE-V1',
      'SM-V1',
      'OP-V1',
    ]);
    raw.execute('PRAGMA user_version = 1;');
  } finally {
    raw.close();
  }
}
