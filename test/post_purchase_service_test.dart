import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_service.dart';

void main() {
  late SpikeDatabase db;
  late PostPurchaseService service;

  setUp(() {
    db = SpikeDatabase.inMemory();
    service = PostPurchaseService(db);
  });

  tearDown(() => db.close());

  test('cash purchase atomically increases stock updates WAC and balances journal', () async {
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

    final result = await service.execute(_command(
      operationId: 'op-pur-cash-1',
      lines: const [
        PostPurchaseLineInput(
          productId: 'P-1',
          quantityScaled: 10 * 1000000,
          unitCostScaled: 70 * 10000,
        ),
      ],
    ));

    expect(result.documentNo, 'PUR-2026-000001');
    expect(result.paymentId, isNotNull);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 20 * 1000000);
    expect(balance.inventoryValueScaled, 1200 * 10000);
    expect(balance.wacUnitCostScaled, 60 * 10000);
    expect((await db.select(db.purchaseItems).get()).length, 1);
    expect((await db.select(db.stockMovementItems).get()).single.quantityScaled, 10 * 1000000);
    expect((await db.select(db.purchasePayments).get()).length, 1);

    final journal = await db.select(db.journalLines).get();
    final debit = journal.fold<int>(0, (sum, row) => sum + row.baseDebitScaled);
    final credit = journal.fold<int>(0, (sum, row) => sum + row.baseCreditScaled);
    expect(debit, credit);
    expect(debit, 700 * 10000);
  });

  test('credit purchase creates supplier liability and no cash payment', () async {
    final result = await service.execute(_command(
      operationId: 'op-pur-credit-1',
      supplierId: 'SUP-1',
      settlementMode: PurchaseSettlementMode.credit,
      lines: const [
        PostPurchaseLineInput(
          productId: 'P-2',
          quantityScaled: 4 * 1000000,
          unitCostScaled: 25 * 10000,
        ),
      ],
    ));

    expect(result.paymentId, isNull);
    expect(await db.select(db.purchasePayments).get(), isEmpty);
    final ledger = await db.select(db.supplierLedger).getSingle();
    expect(ledger.supplierId, 'SUP-1');
    expect(ledger.creditScaled, 100 * 10000);
    expect(ledger.baseCreditScaled, 100 * 10000);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 4 * 1000000);
    expect(balance.inventoryValueScaled, 100 * 10000);
    expect(balance.wacUnitCostScaled, 25 * 10000);
  });

  test('duplicate product lines aggregate into one WAC balance update while preserving detail', () async {
    await service.execute(_command(
      operationId: 'op-pur-dup-1',
      lines: const [
        PostPurchaseLineInput(productId: 'P-1', quantityScaled: 2 * 1000000, unitCostScaled: 40 * 10000),
        PostPurchaseLineInput(productId: 'P-1', quantityScaled: 3 * 1000000, unitCostScaled: 60 * 10000),
      ],
    ));

    expect((await db.select(db.purchaseItems).get()).length, 2);
    expect((await db.select(db.stockMovementItems).get()).length, 2);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 5 * 1000000);
    expect(balance.inventoryValueScaled, 260 * 10000);
    expect(balance.wacUnitCostScaled, 52 * 10000);
  });

  test('same operation id is idempotent and does not duplicate purchase truth', () async {
    final command = _command(
      operationId: 'op-pur-idem-1',
      lines: const [
        PostPurchaseLineInput(productId: 'P-1', quantityScaled: 1 * 1000000, unitCostScaled: 80 * 10000),
      ],
    );
    final first = await service.execute(command);
    final replay = await service.execute(command);

    expect(first.purchaseId, replay.purchaseId);
    expect(replay.idempotentReplay, isTrue);
    expect((await db.select(db.purchases).get()).length, 1);
    expect((await db.select(db.operationLog).get()).length, 1);
    expect((await db.select(db.auditLogs).get()).length, 1);
  });

  test('credit purchase without supplier is rejected before canonical writes', () async {
    await expectLater(
      service.execute(_command(
        operationId: 'op-pur-invalid-1',
        settlementMode: PurchaseSettlementMode.credit,
        lines: const [
          PostPurchaseLineInput(productId: 'P-1', quantityScaled: 1 * 1000000, unitCostScaled: 80 * 10000),
        ],
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.purchases).get(), isEmpty);
    expect(await db.select(db.inventoryBalances).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
  });
}

PostPurchaseCommand _command({
  required String operationId,
  required List<PostPurchaseLineInput> lines,
  String? supplierId,
  PurchaseSettlementMode settlementMode = PurchaseSettlementMode.cash,
}) {
  return PostPurchaseCommand(
    operationId: operationId,
    businessId: 'B-1',
    userId: 'U-1',
    warehouseId: 'WH-1',
    supplierId: supplierId,
    settlementMode: settlementMode,
    currencyCode: 'YER',
    baseCurrencyCode: 'YER',
    exchangeRateScaled: 100000000,
    inventoryLedgerAccountId: 'ACC-INV',
    accountsPayableLedgerAccountId: 'ACC-AP',
    cashAccountId: 'CASH-1',
    cashLedgerAccountId: 'ACC-CASH',
    purchaseAt: DateTime.utc(2026, 8, 11, 12),
    lines: lines,
  );
}