import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/backup/encrypted_backup_service.dart';
import 'package:ibex_foundation_spike/database/encrypted_database_opener.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';

void main() {
  const goodKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const wrongKey = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ibex_encryption_gate_');
    dbFile = File('${tempDir.path}${Platform.pathSeparator}ibex.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('database file is encrypted and correct key can reopen persisted truth', () async {
    final db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: goodKey),
    );
    await _seedAndPostSale(db);
    await db.close();

    final header = await dbFile.openRead(0, 16).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final sqliteHeader = 'SQLite format 3\u0000'.codeUnits;
    expect(header, isNot(equals(sqliteHeader)));

    final reopened = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: goodKey),
    );
    expect((await reopened.select(reopened.sales).get()).length, 1);
    expect((await reopened.select(reopened.journalEntries).get()).length, 1);
    final sale = await reopened.select(reopened.sales).getSingle();
    expect(sale.baseCurrencyCode, 'YER');
    final balance = await reopened.select(reopened.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 8 * 1000000);
    await reopened.close();
  });

  test('wrong key is rejected before domain reads are allowed', () async {
    final db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: goodKey),
    );
    await db.customSelect('SELECT 1').get();
    await db.close();

    final wrong = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: wrongKey),
    );
    await expectLater(
      wrong.customSelect('SELECT count(*) FROM sqlite_master').get(),
      throwsA(anything),
    );
    try {
      await wrong.close();
    } catch (_) {
      // A failed open may also make executor shutdown report the original open error.
    }
  });

  test('encrypted backup restore reproduces operational truth and balances', () async {
    final db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: goodKey),
    );
    await _seedAndPostSale(db);
    await db.close();

    final backupDir = Directory('${tempDir.path}${Platform.pathSeparator}backup');
    const backup = EncryptedBackupService();
    final manifest = await backup.createClosedDatabaseBackup(
      sourceDatabase: dbFile,
      destinationDirectory: backupDir,
      schemaVersion: 2,
    );
    expect(manifest.databaseSha256, hasLength(64));
    expect(manifest.schemaVersion, 2);

    await dbFile.delete();
    expect(await dbFile.exists(), isFalse);

    await backup.restoreValidatedBackup(
      backupDirectory: backupDir,
      targetDatabase: dbFile,
    );

    final restored = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: goodKey),
    );
    expect((await restored.select(restored.sales).get()).length, 1);
    expect((await restored.select(restored.saleItems).get()).length, 1);
    expect((await restored.select(restored.stockMovements).get()).length, 1);
    expect((await restored.select(restored.journalEntries).get()).length, 1);
    expect((await restored.select(restored.journalLines).get()).length, 4);
    expect((await restored.select(restored.payments).get()).length, 1);
    expect((await restored.select(restored.operationLog).get()).length, 1);
    expect((await restored.select(restored.auditLogs).get()).length, 1);

    final restoredSale = await restored.select(restored.sales).getSingle();
    expect(restoredSale.baseCurrencyCode, 'YER');

    final lines = await restored.select(restored.journalLines).get();
    final debit = lines.fold<int>(0, (sum, row) => sum + row.baseDebitScaled);
    final credit = lines.fold<int>(0, (sum, row) => sum + row.baseCreditScaled);
    expect(debit, credit);

    final balance = await restored.select(restored.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 8 * 1000000);
    expect(balance.inventoryValueScaled, 400 * 10000);
    await restored.close();
  });

  test('corrupted encrypted backup fails checksum validation before restore', () async {
    final db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: goodKey),
    );
    await db.customSelect('SELECT 1').get();
    await db.close();

    final backupDir = Directory('${tempDir.path}${Platform.pathSeparator}backup_corrupt');
    const backup = EncryptedBackupService();
    await backup.createClosedDatabaseBackup(
      sourceDatabase: dbFile,
      destinationDirectory: backupDir,
      schemaVersion: 2,
    );

    final backupDb = File('${backupDir.path}${Platform.pathSeparator}ibex.db.enc');
    await backupDb.writeAsBytes([1, 2, 3, 4], mode: FileMode.append, flush: true);

    await expectLater(
      backup.validateBackup(backupDir),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _seedAndPostSale(SpikeDatabase db) async {
  await db.into(db.inventoryBalances).insert(
        InventoryBalancesCompanion.insert(
          warehouseId: 'WH-1',
          productId: 'P-1',
          quantityScaled: 10 * 1000000,
          inventoryValueScaled: 500 * 10000,
          wacUnitCostScaled: 50 * 10000,
          updatedAt: DateTime.utc(2026, 8, 11),
        ),
      );

  await PostSaleService(db).execute(
    PostSaleCommand(
      operationId: 'op-encrypted-sale',
      businessId: 'B-1',
      userId: 'U-1',
      warehouseId: 'WH-1',
      currencyCode: 'YER',
      baseCurrencyCode: 'YER',
      exchangeRateScaled: 100000000,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      salesRevenueAccountId: 'ACC-SALES',
      inventoryLedgerAccountId: 'ACC-INV',
      cogsLedgerAccountId: 'ACC-COGS',
      saleAt: DateTime.utc(2026, 8, 11, 10),
      lines: const [
        PostSaleLineInput(
          productId: 'P-1',
          quantityScaled: 2 * 1000000,
          unitPriceScaled: 80 * 10000,
        ),
      ],
    ),
  );
}
