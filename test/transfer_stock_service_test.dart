import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/transfer_stock_command.dart';
import 'package:ibex_foundation_spike/operating_engine/transfer_stock_service.dart';

void main() {
  late SpikeDatabase db;
  late TransferStockService service;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    service = TransferStockService(db);
    final now = DateTime.utc(2026, 8, 11);
    for (final warehouse in [
      ('WH-A', 'المستودع أ'),
      ('WH-B', 'المستودع ب'),
    ]) {
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              id: warehouse.$1,
              businessId: 'B-1',
              name: warehouse.$2,
              normalizedName: warehouse.$2,
              updatedAt: now,
            ),
          );
    }
    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            warehouseId: 'WH-A',
            productId: 'P-1',
            quantityScaled: 10 * 1000000,
            inventoryValueScaled: 500 * 10000,
            wacUnitCostScaled: 50 * 10000,
            updatedAt: now,
          ),
        );
    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            warehouseId: 'WH-B',
            productId: 'P-1',
            quantityScaled: 2 * 1000000,
            inventoryValueScaled: 120 * 10000,
            wacUnitCostScaled: 60 * 10000,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  TransferStockCommand command({String operationId = 'OP-STX-1'}) => TransferStockCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        sourceWarehouseId: 'WH-A',
        destinationWarehouseId: 'WH-B',
        transferredAt: DateTime.utc(2026, 8, 11),
        lines: const [
          TransferStockLineInput(productId: 'P-1', quantityScaled: 3 * 1000000),
        ],
      );

  test('transfer creates one document and exactly two movements at the same carrying value', () async {
    final result = await service.execute(command());
    expect(result.documentNo, 'STX-2026-000001');
    final transfers = await db.select(db.stockTransfers).get();
    expect(transfers, hasLength(1));
    final movements = await db.select(db.stockMovements).get();
    expect(movements, hasLength(2));
    expect(movements.map((m) => m.movementType).toSet(), {'TRANSFER_OUT', 'TRANSFER_IN'});

    final movementItems = await db.select(db.stockMovementItems).get();
    expect(movementItems, hasLength(2));
    expect(movementItems.map((m) => m.totalCostScaled).toSet(), {-150 * 10000, 150 * 10000});

    final source = await (db.select(db.inventoryBalances)
          ..where((r) => r.warehouseId.equals('WH-A') & r.productId.equals('P-1')))
        .getSingle();
    final destination = await (db.select(db.inventoryBalances)
          ..where((r) => r.warehouseId.equals('WH-B') & r.productId.equals('P-1')))
        .getSingle();
    expect(source.quantityScaled, 7 * 1000000);
    expect(source.inventoryValueScaled, 350 * 10000);
    expect(destination.quantityScaled, 5 * 1000000);
    expect(destination.inventoryValueScaled, 270 * 10000);
    expect(destination.wacUnitCostScaled, 54 * 10000);
    expect(await db.select(db.journalEntries).get(), isEmpty);
  });

  test('duplicate product lines aggregate stock validation but preserve line detail', () async {
    final duplicate = TransferStockCommand(
      operationId: 'OP-STX-DUP',
      businessId: 'B-1',
      userId: 'U-1',
      sourceWarehouseId: 'WH-A',
      destinationWarehouseId: 'WH-B',
      transferredAt: DateTime.utc(2026, 8, 11),
      lines: const [
        TransferStockLineInput(productId: 'P-1', quantityScaled: 2 * 1000000),
        TransferStockLineInput(productId: 'P-1', quantityScaled: 1 * 1000000),
      ],
    );
    await service.execute(duplicate);
    expect(await db.select(db.stockTransferItems).get(), hasLength(2));
    expect(await db.select(db.stockMovementItems).get(), hasLength(4));
  });

  test('insufficient aggregate stock rolls back document, movements and balances', () async {
    final invalid = TransferStockCommand(
      operationId: 'OP-STX-OVER',
      businessId: 'B-1',
      userId: 'U-1',
      sourceWarehouseId: 'WH-A',
      destinationWarehouseId: 'WH-B',
      transferredAt: DateTime.utc(2026, 8, 11),
      lines: const [
        TransferStockLineInput(productId: 'P-1', quantityScaled: 6 * 1000000),
        TransferStockLineInput(productId: 'P-1', quantityScaled: 5 * 1000000),
      ],
    );
    await expectLater(service.execute(invalid), throwsA(isA<Exception>()));
    expect(await db.select(db.stockTransfers).get(), isEmpty);
    expect(await db.select(db.stockMovements).get(), isEmpty);
    final source = await (db.select(db.inventoryBalances)
          ..where((r) => r.warehouseId.equals('WH-A')))
        .getSingle();
    expect(source.quantityScaled, 10 * 1000000);
  });

  test('same operation is idempotent and does not duplicate transfer truth', () async {
    final first = await service.execute(command());
    final second = await service.execute(command());
    expect(first.transferId, second.transferId);
    expect(second.idempotentReplay, isTrue);
    expect(await db.select(db.stockTransfers).get(), hasLength(1));
    expect(await db.select(db.stockMovements).get(), hasLength(2));
  });

  test('same source and destination warehouse is rejected', () async {
    final invalid = TransferStockCommand(
      operationId: 'OP-STX-SAME',
      businessId: 'B-1',
      userId: 'U-1',
      sourceWarehouseId: 'WH-A',
      destinationWarehouseId: 'WH-A',
      transferredAt: DateTime.utc(2026, 8, 11),
      lines: const [TransferStockLineInput(productId: 'P-1', quantityScaled: 1000000)],
    );
    await expectLater(service.execute(invalid), throwsA(isA<Exception>()));
    expect(await db.select(db.stockTransfers).get(), isEmpty);
  });
}
