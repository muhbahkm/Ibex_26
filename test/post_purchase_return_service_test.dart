import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_return_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_return_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_service.dart';

void main() {
  late SpikeDatabase db;
  late PostPurchaseService purchases;
  late PostPurchaseReturnService returns;
  final now = DateTime.utc(2026, 8, 11);

  setUp(() async {
    db = SpikeDatabase.inMemory();
    purchases = PostPurchaseService(db);
    returns = PostPurchaseReturnService(db);
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            id: 'WH-1',
            businessId: 'B-1',
            name: 'الرئيسي',
            normalizedName: 'الرئيسي',
            updatedAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<(String purchaseId, String itemId)> postPurchase({
    PurchaseSettlementMode settlement = PurchaseSettlementMode.cash,
    String operationId = 'OP-PUR-1',
  }) async {
    final result = await purchases.execute(
      PostPurchaseCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        warehouseId: 'WH-1',
        supplierId: settlement == PurchaseSettlementMode.credit ? 'S-1' : null,
        settlementMode: settlement,
        currencyCode: 'SAR',
        baseCurrencyCode: 'SAR',
        exchangeRateScaled: 100000000,
        inventoryLedgerAccountId: 'ACC-INV',
        accountsPayableLedgerAccountId: 'ACC-AP',
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        purchaseAt: now,
        lines: const [
          PostPurchaseLineInput(
            productId: 'P-1',
            quantityScaled: 4 * 1000000,
            unitCostScaled: 100 * 10000,
          ),
        ],
      ),
    );
    final item = await (db.select(db.purchaseItems)
          ..where((r) => r.purchaseId.equals(result.purchaseId)))
        .getSingle();
    return (result.purchaseId, item.id);
  }

  PostPurchaseReturnCommand returnCommand({
    required String purchaseId,
    required String purchaseItemId,
    int quantityScaled = 2 * 1000000,
    String operationId = 'OP-PRT-1',
  }) => PostPurchaseReturnCommand(
        operationId: operationId,
        businessId: 'B-1',
        userId: 'U-1',
        sourcePurchaseId: purchaseId,
        cashAccountId: 'CASH-1',
        cashLedgerAccountId: 'ACC-CASH',
        inventoryLedgerAccountId: 'ACC-INV',
        accountsPayableLedgerAccountId: 'ACC-AP',
        returnedAt: now,
        lines: [
          PostPurchaseReturnLineInput(
            sourcePurchaseItemId: purchaseItemId,
            quantityScaled: quantityScaled,
          ),
        ],
      );

  test('cash purchase return removes source cost and records cash receipt atomically', () async {
    final source = await postPurchase();
    final result = await returns.execute(
      returnCommand(purchaseId: source.$1, purchaseItemId: source.$2),
    );
    expect(result.documentNo, 'PRT-2026-000001');
    expect(result.cashReceiptId, isNotNull);
    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 2 * 1000000);
    expect(balance.inventoryValueScaled, 200 * 10000);
    expect(balance.wacUnitCostScaled, 100 * 10000);
    expect(await db.select(db.purchaseReturnCashReceipts).get(), hasLength(1));
    final lines = await (db.select(db.journalLines)
          ..where((r) => r.journalEntryId.equals(result.journalEntryId)))
        .get();
    expect(lines.fold<int>(0, (s, l) => s + l.baseDebitScaled),
        lines.fold<int>(0, (s, l) => s + l.baseCreditScaled));
  });

  test('credit purchase return reduces supplier payable without cash receipt', () async {
    final source = await postPurchase(
      settlement: PurchaseSettlementMode.credit,
      operationId: 'OP-PUR-CREDIT',
    );
    final before = await db.select(db.supplierLedger).getSingle();
    expect(before.creditScaled, 400 * 10000);
    await returns.execute(returnCommand(
      purchaseId: source.$1,
      purchaseItemId: source.$2,
      operationId: 'OP-PRT-CREDIT',
    ));
    final ledger = await db.select(db.supplierLedger).get();
    expect(ledger, hasLength(2));
    expect(ledger.fold<int>(0, (s, r) => s + r.creditScaled - r.debitScaled), 200 * 10000);
    expect(await db.select(db.purchaseReturnCashReceipts).get(), isEmpty);
  });

  test('cumulative purchase returns cannot exceed source quantity', () async {
    final source = await postPurchase();
    await returns.execute(returnCommand(
      purchaseId: source.$1,
      purchaseItemId: source.$2,
      quantityScaled: 3 * 1000000,
      operationId: 'OP-PRT-A',
    ));
    await expectLater(
      returns.execute(returnCommand(
        purchaseId: source.$1,
        purchaseItemId: source.$2,
        quantityScaled: 2 * 1000000,
        operationId: 'OP-PRT-B',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.purchaseReturns).get(), hasLength(1));
  });

  test('purchase return is idempotent by operation id', () async {
    final source = await postPurchase();
    final command = returnCommand(purchaseId: source.$1, purchaseItemId: source.$2);
    final first = await returns.execute(command);
    final second = await returns.execute(command);
    expect(first.purchaseReturnId, second.purchaseReturnId);
    expect(second.idempotentReplay, isTrue);
    expect(await db.select(db.purchaseReturns).get(), hasLength(1));
  });

  test('return item from another purchase is rejected without partial truth', () async {
    final sourceA = await postPurchase(operationId: 'OP-PUR-A');
    final sourceB = await postPurchase(operationId: 'OP-PUR-B');

    await expectLater(
      returns.execute(returnCommand(
        purchaseId: sourceA.$1,
        purchaseItemId: sourceB.$2,
        operationId: 'OP-PRT-WRONG-LINE',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.purchaseReturns).get(), isEmpty);
    expect(await db.select(db.purchaseReturnItems).get(), isEmpty);
  });

  test('non-positive return quantity is rejected before numbering or mutation', () async {
    final source = await postPurchase();
    await expectLater(
      returns.execute(returnCommand(
        purchaseId: source.$1,
        purchaseItemId: source.$2,
        quantityScaled: 0,
        operationId: 'OP-PRT-ZERO',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.purchaseReturns).get(), isEmpty);
    final sequenceRows = await db.customSelect(
      "SELECT * FROM document_sequences WHERE document_type = 'purchase_return'",
    ).get();
    expect(sequenceRows, isEmpty);
  });

  test('return fails atomically when current stock is below requested source quantity', () async {
    final source = await postPurchase();
    await db.customStatement(
      'UPDATE inventory_balances SET quantity_scaled = ?, inventory_value_scaled = ?, wac_unit_cost_scaled = ? WHERE warehouse_id = ? AND product_id = ?',
      [1000000, 100 * 10000, 100 * 10000, 'WH-1', 'P-1'],
    );

    await expectLater(
      returns.execute(returnCommand(
        purchaseId: source.$1,
        purchaseItemId: source.$2,
        quantityScaled: 2 * 1000000,
        operationId: 'OP-PRT-NO-STOCK',
      )),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.purchaseReturns).get(), isEmpty);
    expect(await db.select(db.purchaseReturnItems).get(), isEmpty);
    expect(await db.select(db.stockMovements).get(), hasLength(1));
  });
}
