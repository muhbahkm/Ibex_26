import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_return_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_return_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';

void main() {
  late SpikeDatabase db;
  late PostSaleService sales;
  late PostSaleReturnService returns;
  final now = DateTime.utc(2026, 8, 11);

  setUp(() async {
    db = SpikeDatabase.inMemory();
    sales = PostSaleService(db);
    returns = PostSaleReturnService(db);
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            id: 'WH-1',
            businessId: 'B-1',
            name: 'المستودع الرئيسي',
            normalizedName: 'المستودع الرئيسي',
            updatedAt: now,
          ),
        );
    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            warehouseId: 'WH-1',
            productId: 'P-1',
            quantityScaled: 10 * 1000000,
            inventoryValueScaled: 500 * 10000,
            wacUnitCostScaled: 50 * 10000,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<(String saleId, String saleItemId)> postSourceSale({
    SaleSettlementMode settlement = SaleSettlementMode.cash,
    String operationId = 'OP-SALE-SOURCE',
  }) async {
    final result = await sales.execute(
      PostSaleCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        warehouseId: 'WH-1',
        customerId: settlement == SaleSettlementMode.credit ? 'C-1' : null,
        settlementMode: settlement,
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        salesRevenueAccountId: 'ACC-SALES',
        inventoryLedgerAccountId: 'ACC-INV',
        cogsLedgerAccountId: 'ACC-COGS',
        accountsReceivableLedgerAccountId: 'ACC-AR',
        saleAt: now,
        lines: const [
          PostSaleLineInput(
            productId: 'P-1',
            quantityScaled: 4 * 1000000,
            unitPriceScaled: 100 * 10000,
          ),
        ],
      ),
    );
    final item = await (db.select(db.saleItems)..where((r) => r.saleId.equals(result.saleId))).getSingle();
    return (result.saleId, item.id);
  }

  PostSaleReturnCommand returnCommand({
    required String saleId,
    required String saleItemId,
    int quantityScaled = 2 * 1000000,
    String operationId = 'OP-SRT-1',
  }) => PostSaleReturnCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        sourceSaleId: saleId,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        salesRevenueAccountId: 'ACC-SALES',
        inventoryLedgerAccountId: 'ACC-INV',
        cogsLedgerAccountId: 'ACC-COGS',
        accountsReceivableLedgerAccountId: 'ACC-AR',
        returnedAt: now,
        lines: [
          PostSaleReturnLineInput(
            sourceSaleItemId: saleItemId,
            quantityScaled: quantityScaled,
          ),
        ],
      );

  test('cash sale return restores original carrying cost and posts refund atomically', () async {
    final source = await postSourceSale();
    final result = await returns.execute(returnCommand(saleId: source.$1, saleItemId: source.$2));
    expect(result.documentNo, 'SRT-2026-000001');
    expect(result.refundPaymentId, isNotNull);

    final saleReturn = await db.select(db.saleReturns).getSingle();
    expect(saleReturn.totalScaled, 200 * 10000);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 8 * 1000000);
    expect(balance.inventoryValueScaled, 400 * 10000);
    expect(balance.wacUnitCostScaled, 50 * 10000);

    final movement = await (db.select(db.stockMovements)
          ..where((r) => r.referenceType.equals('sales_return')))
        .getSingle();
    expect(movement.movementType, 'SALE_RETURN_IN');
    final journal = await (db.select(db.journalLines)
          ..where((r) => r.journalEntryId.equals(result.journalEntryId)))
        .get();
    expect(journal.fold<int>(0, (s, l) => s + l.baseDebitScaled),
        journal.fold<int>(0, (s, l) => s + l.baseCreditScaled));
    expect(await db.select(db.saleRefundPayments).get(), hasLength(1));
  });

  test('cumulative return quantity cannot exceed source sale quantity', () async {
    final source = await postSourceSale();
    await returns.execute(returnCommand(
      saleId: source.$1,
      saleItemId: source.$2,
      quantityScaled: 3 * 1000000,
      operationId: 'OP-SRT-A',
    ));
    await expectLater(
      returns.execute(returnCommand(
        saleId: source.$1,
        saleItemId: source.$2,
        quantityScaled: 2 * 1000000,
        operationId: 'OP-SRT-B',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.saleReturns).get(), hasLength(1));
  });

  test('credit sale return reduces receivable and does not create cash refund', () async {
    final source = await postSourceSale(
      settlement: SaleSettlementMode.credit,
      operationId: 'OP-SALE-CREDIT',
    );
    final before = await db.select(db.customerLedger).get();
    expect(before.single.debitScaled, 400 * 10000);

    await returns.execute(returnCommand(
      saleId: source.$1,
      saleItemId: source.$2,
      operationId: 'OP-SRT-CREDIT',
    ));
    final ledger = await db.select(db.customerLedger).get();
    expect(ledger, hasLength(2));
    expect(ledger.fold<int>(0, (s, row) => s + row.debitScaled - row.creditScaled), 200 * 10000);
    expect(await db.select(db.saleRefundPayments).get(), isEmpty);
  });

  test('same return operation id is idempotent', () async {
    final source = await postSourceSale();
    final command = returnCommand(saleId: source.$1, saleItemId: source.$2);
    final first = await returns.execute(command);
    final second = await returns.execute(command);
    expect(first.saleReturnId, second.saleReturnId);
    expect(second.idempotentReplay, isTrue);
    expect(await db.select(db.saleReturns).get(), hasLength(1));
    expect(await db.select(db.stockMovements).get(), hasLength(2));
  });

  test('return line from another sale is rejected before return truth is written', () async {
    final sourceA = await postSourceSale(operationId: 'OP-SALE-A');
    final sourceB = await postSourceSale(operationId: 'OP-SALE-B');
    await expectLater(
      returns.execute(returnCommand(
        saleId: sourceA.$1,
        saleItemId: sourceB.$2,
        operationId: 'OP-SRT-WRONG-LINE',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.saleReturns).get(), isEmpty);
  });
}
