import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/core/time/business_document_calendar.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';

void main() {
  test('sale near UTC year boundary uses UTC+3 business year in document number', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 12, 31, 22, 30);

    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            warehouseId: 'WH-1',
            productId: 'P-1',
            quantityScaled: 10 * 1000000,
            inventoryValueScaled: 1000 * 10000,
            wacUnitCostScaled: 100 * 10000,
            updatedAt: now,
          ),
        );

    final service = PostSaleService(
      db,
      calendar: const FixedOffsetBusinessDocumentCalendar(180),
    );
    final result = await service.execute(
      PostSaleCommand(
        operationId: 'OP-CALENDAR-1',
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
        saleAt: now,
        lines: const [
          PostSaleLineInput(
            productId: 'P-1',
            quantityScaled: 1000000,
            unitPriceScaled: 500 * 10000,
          ),
        ],
      ),
    );

    expect(result.documentNo, 'SAL-2027-000001');
    final sequence = await db.select(db.documentSequences).getSingle();
    expect(sequence.scopeKey, '2027');
  });
}
