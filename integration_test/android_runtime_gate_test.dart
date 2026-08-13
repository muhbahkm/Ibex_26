import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:ibex_foundation_spike/backup/encrypted_backup_service.dart';
import 'package:ibex_foundation_spike/database/encrypted_database_opener.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';
import 'package:ibex_foundation_spike/security/secure_database_key_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android runtime preserves encrypted operational truth and secure key', (tester) async {
    final appDir = await getApplicationDocumentsDirectory();
    final gateDir = Directory(p.join(appDir.path, 'ibex_runtime_gate'));
    if (await gateDir.exists()) await gateDir.delete(recursive: true);
    await gateDir.create(recursive: true);

    final dbFile = File(p.join(gateDir.path, 'ibex.db'));
    final backupDir = Directory(p.join(gateDir.path, 'backup'));
    final keyStore = SecureDatabaseKeyStore();
    await keyStore.deleteKeyForSpikeTestOnly();

    final firstKey = await keyStore.loadOrCreateHexKey();
    expect(firstKey, hasLength(64));
    expect(await keyStore.readHexKey(), firstKey);
    expect(await keyStore.loadOrCreateHexKey(), firstKey);

    var db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: firstKey),
    );
    await _seedAndPostSale(db);
    expect((await db.select(db.sales).get()).length, 1);
    await db.close();

    final header = await dbFile.openRead(0, 16).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    expect(header, isNot(equals('SQLite format 3\u0000'.codeUnits)));

    db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: await keyStore.loadOrCreateHexKey()),
    );
    final persistedSale = await db.select(db.sales).getSingle();
    expect(persistedSale.documentNo, 'SAL-2026-000001');
    expect(persistedSale.baseCurrencyCode, 'YER');
    expect((await db.select(db.journalLines).get()).length, 4);
    await db.close();

    final wrongKey = firstKey.substring(0, 63) + (firstKey.endsWith('0') ? '1' : '0');
    final wrongDb = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: wrongKey),
    );
    await expectLater(
      wrongDb.customSelect('SELECT count(*) FROM sqlite_master').get(),
      throwsA(anything),
    );
    try {
      await wrongDb.close();
    } catch (_) {
      // The executor can surface the same failed-open error again on shutdown.
    }

    const backup = EncryptedBackupService();
    final manifest = await backup.createClosedDatabaseBackup(
      sourceDatabase: dbFile,
      destinationDirectory: backupDir,
      schemaVersion: 6,
    );
    expect(manifest.schemaVersion, 6);
    expect(manifest.databaseSha256, hasLength(64));

    await dbFile.delete();
    expect(await dbFile.exists(), isFalse);
    await backup.restoreValidatedBackup(
      backupDirectory: backupDir,
      targetDatabase: dbFile,
    );

    db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: dbFile, hexKey: await keyStore.loadOrCreateHexKey()),
    );
    expect((await db.select(db.sales).get()).length, 1);
    expect((await db.select(db.saleItems).get()).length, 1);
    expect((await db.select(db.stockMovements).get()).length, 1);
    expect((await db.select(db.payments).get()).length, 1);
    expect((await db.select(db.operationLog).get()).length, 1);
    expect((await db.select(db.auditLogs).get()).length, 1);

    final journalLines = await db.select(db.journalLines).get();
    final debit = journalLines.fold<int>(0, (sum, row) => sum + row.baseDebitScaled);
    final credit = journalLines.fold<int>(0, (sum, row) => sum + row.baseCreditScaled);
    expect(debit, credit);

    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 8 * 1000000);
    expect(balance.inventoryValueScaled, 400 * 10000);
    await db.close();

    expect(await keyStore.readHexKey(), firstKey);
  });
}

Future<void> _seedAndPostSale(SpikeDatabase db) async {
  await db.into(db.inventoryBalances).insert(
        InventoryBalancesCompanion.insert(
          warehouseId: 'WH-ANDROID',
          productId: 'P-SIDR',
          quantityScaled: 10 * 1000000,
          inventoryValueScaled: 500 * 10000,
          wacUnitCostScaled: 50 * 10000,
          updatedAt: DateTime.utc(2026, 8, 11),
        ),
      );

  await PostSaleService(db).execute(
    PostSaleCommand(
      operationId: 'op-android-runtime-sale',
      businessId: 'B-ANDROID',
      userId: 'U-ANDROID',
      warehouseId: 'WH-ANDROID',
      currencyCode: 'YER',
      baseCurrencyCode: 'YER',
      exchangeRateScaled: 100000000,
      cashAccountId: 'CASH-ANDROID',
      cashLedgerAccountId: 'ACC-CASH',
      salesRevenueAccountId: 'ACC-SALES',
      inventoryLedgerAccountId: 'ACC-INV',
      cogsLedgerAccountId: 'ACC-COGS',
      saleAt: DateTime.utc(2026, 8, 11, 10),
      lines: const [
        PostSaleLineInput(
          productId: 'P-SIDR',
          quantityScaled: 2 * 1000000,
          unitPriceScaled: 80 * 10000,
        ),
      ],
    ),
  );
}
