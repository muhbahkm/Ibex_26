import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';

void main() {
  late SpikeDatabase db;
  late PostSaleService service;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    service = PostSaleService(db);
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
  });

  tearDown(() => db.close());

  PostSaleCommand command({
    String operationId = 'op-sale-1',
    int qty = 2 * 1000000,
    String currencyCode = 'YER',
    String baseCurrencyCode = 'YER',
    int exchangeRateScaled = 100000000,
    List<PostSaleLineInput>? lines,
  }) {
    return PostSaleCommand(
      operationId: operationId,
      businessId: 'B-1',
      userId: 'U-1',
      warehouseId: 'WH-1',
      currencyCode: currencyCode,
      baseCurrencyCode: baseCurrencyCode,
      exchangeRateScaled: exchangeRateScaled,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      salesRevenueAccountId: 'ACC-SALES',
      inventoryLedgerAccountId: 'ACC-INV',
      cogsLedgerAccountId: 'ACC-COGS',
      saleAt: DateTime.utc(2026, 8, 11, 10),
      lines: lines ??
          [
            PostSaleLineInput(
              productId: 'P-1',
              quantityScaled: qty,
              unitPriceScaled: 80 * 10000,
            ),
          ],
    );
  }

  test('PostSale atomically creates sale, stock, journal, payment, operation and audit', () async {
    final result = await service.execute(command());

    expect(result.documentNo, 'SAL-2026-000001');
    expect((await db.select(db.sales).get()).length, 1);
    expect((await db.select(db.stockMovements).get()).length, 1);
    expect((await db.select(db.stockMovementItems).get()).length, 1);
    expect((await db.select(db.journalEntries).get()).length, 1);
    expect((await db.select(db.journalLines).get()).length, 4);
    expect((await db.select(db.payments).get()).length, 1);
    expect((await db.select(db.operationLog).get()).length, 1);
    expect((await db.select(db.auditLogs).get()).length, 1);

    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 8 * 1000000);
    expect(balance.inventoryValueScaled, 400 * 10000);

    final lines = await db.select(db.journalLines).get();
    final debit = lines.fold<int>(0, (sum, line) => sum + line.baseDebitScaled);
    final credit = lines.fold<int>(0, (sum, line) => sum + line.baseCreditScaled);
    expect(debit, credit);
  });

  test('same operation id is idempotent and does not duplicate truth', () async {
    final first = await service.execute(command());
    final second = await service.execute(command());

    expect(second.idempotentReplay, isTrue);
    expect(second.saleId, first.saleId);
    expect(second.documentNo, first.documentNo);
    expect((await db.select(db.sales).get()).length, 1);
    expect((await db.select(db.payments).get()).length, 1);
    expect((await db.select(db.operationLog).get()).length, 1);
  });

  test('insufficient stock rolls back complete operation', () async {
    await expectLater(
      service.execute(command(operationId: 'op-fail', qty: 11 * 1000000)),
      throwsA(predicate((e) => e.toString().contains('INV_INSUFFICIENT_STOCK'))),
    );

    await _expectNoPostedTruth(db);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 10 * 1000000);
    expect(balance.inventoryValueScaled, 500 * 10000);
  });

  test('duplicate product lines are aggregated before stock validation', () async {
    final duplicateLines = [
      const PostSaleLineInput(
        productId: 'P-1',
        quantityScaled: 6 * 1000000,
        unitPriceScaled: 80 * 10000,
      ),
      const PostSaleLineInput(
        productId: 'P-1',
        quantityScaled: 5 * 1000000,
        unitPriceScaled: 80 * 10000,
      ),
    ];

    await expectLater(
      service.execute(command(operationId: 'op-duplicate-overdraw', lines: duplicateLines)),
      throwsA(predicate((e) => e.toString().contains('INV_INSUFFICIENT_STOCK'))),
    );

    await _expectNoPostedTruth(db);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 10 * 1000000);
  });

  test('duplicate product lines within available stock update balance once correctly', () async {
    final result = await service.execute(
      command(
        operationId: 'op-duplicate-valid',
        lines: const [
          PostSaleLineInput(
            productId: 'P-1',
            quantityScaled: 2 * 1000000,
            unitPriceScaled: 80 * 10000,
          ),
          PostSaleLineInput(
            productId: 'P-1',
            quantityScaled: 3 * 1000000,
            unitPriceScaled: 85 * 10000,
          ),
        ],
      ),
    );

    expect(result.documentNo, 'SAL-2026-000001');
    expect((await db.select(db.saleItems).get()).length, 2);
    expect((await db.select(db.stockMovementItems).get()).length, 2);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 5 * 1000000);
    expect(balance.inventoryValueScaled, 250 * 10000);
  });

  test('base currency is command-owned and not hard-coded to YER', () async {
    await service.execute(
      command(
        operationId: 'op-sar-base',
        currencyCode: 'USD',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 375000000,
      ),
    );

    final sale = await db.select(db.sales).getSingle();
    expect(sale.totalScaled, 160 * 10000);
    expect(sale.baseTotalScaled, 600 * 10000);
  });

  test('failure after document sequence rolls sequence and all truth back', () async {
    service = PostSaleService(
      db,
      failureInjector: (point) {
        if (point == 'after_sequence') throw StateError('injected failure');
      },
    );

    await expectLater(service.execute(command(operationId: 'op-sequence-fail')), throwsStateError);

    await _expectNoPostedTruth(db);
    expect(await db.select(db.documentSequences).get(), isEmpty);

    service = PostSaleService(db);
    final recovered = await service.execute(command(operationId: 'op-sequence-retry'));
    expect(recovered.documentNo, 'SAL-2026-000001');
  });

  test('failure after inventory write rolls stock, sequence and partial records back', () async {
    service = PostSaleService(
      db,
      failureInjector: (point) {
        if (point == 'after_first_inventory_write') {
          throw StateError('injected inventory failure');
        }
      },
    );

    await expectLater(service.execute(command(operationId: 'op-inventory-fail')), throwsStateError);

    await _expectNoPostedTruth(db);
    expect(await db.select(db.documentSequences).get(), isEmpty);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 10 * 1000000);
    expect(balance.inventoryValueScaled, 500 * 10000);
  });

  test('failure immediately before commit rolls every persisted effect back', () async {
    service = PostSaleService(
      db,
      failureInjector: (point) {
        if (point == 'before_commit') throw StateError('injected commit failure');
      },
    );

    await expectLater(service.execute(command(operationId: 'op-before-commit-fail')), throwsStateError);

    await _expectNoPostedTruth(db);
    expect(await db.select(db.documentSequences).get(), isEmpty);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 10 * 1000000);
    expect(balance.inventoryValueScaled, 500 * 10000);
  });
}

Future<void> _expectNoPostedTruth(SpikeDatabase db) async {
  expect(await db.select(db.sales).get(), isEmpty);
  expect(await db.select(db.saleItems).get(), isEmpty);
  expect(await db.select(db.stockMovements).get(), isEmpty);
  expect(await db.select(db.stockMovementItems).get(), isEmpty);
  expect(await db.select(db.journalEntries).get(), isEmpty);
  expect(await db.select(db.journalLines).get(), isEmpty);
  expect(await db.select(db.payments).get(), isEmpty);
  expect(await db.select(db.operationLog).get(), isEmpty);
  expect(await db.select(db.auditLogs).get(), isEmpty);
}
