import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/runtime/spike_runtime_config.dart';

void main() {
  test('spike config explicitly opts into demo seed', () {
    const config = SpikeRuntimeConfig();
    expect(config.seedDemoData, isTrue);
  });

  test('production config always disables demo seed', () {
    const config = SpikeRuntimeConfig.production(
      businessId: 'B-PROD',
      userId: 'U-OWNER',
      defaultWarehouseId: 'WH-MAIN',
      baseCurrencyCode: 'YER',
      cashAccountId: 'CASH-MAIN',
      cashLedgerAccountId: 'ACC-CASH',
      salesRevenueAccountId: 'ACC-SALES',
      inventoryLedgerAccountId: 'ACC-INVENTORY',
      cogsLedgerAccountId: 'ACC-COGS',
      accountsReceivableLedgerAccountId: 'ACC-AR',
    );

    expect(config.seedDemoData, isFalse);
    expect(config.businessId, 'B-PROD');
  });
}
