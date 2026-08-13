class SpikeRuntimeConfig {
  const SpikeRuntimeConfig({
    this.businessId = 'B-LOCAL-DEMO',
    this.userId = 'U-LOCAL-DEMO',
    this.defaultWarehouseId = 'WH-MAIN',
    this.baseCurrencyCode = 'YER',
    this.cashAccountId = 'CASH-MAIN',
    this.cashLedgerAccountId = 'ACC-CASH',
    this.salesRevenueAccountId = 'ACC-SALES',
    this.inventoryLedgerAccountId = 'ACC-INVENTORY',
    this.cogsLedgerAccountId = 'ACC-COGS',
    this.accountsReceivableLedgerAccountId = 'ACC-AR',
    this.seedDemoData = true,
  });

  const SpikeRuntimeConfig.production({
    required this.businessId,
    required this.userId,
    required this.defaultWarehouseId,
    required this.baseCurrencyCode,
    required this.cashAccountId,
    required this.cashLedgerAccountId,
    required this.salesRevenueAccountId,
    required this.inventoryLedgerAccountId,
    required this.cogsLedgerAccountId,
    required this.accountsReceivableLedgerAccountId,
  }) : seedDemoData = false;

  final String businessId;
  final String userId;
  final String defaultWarehouseId;
  final String baseCurrencyCode;
  final String cashAccountId;
  final String cashLedgerAccountId;
  final String salesRevenueAccountId;
  final String inventoryLedgerAccountId;
  final String cogsLedgerAccountId;
  final String accountsReceivableLedgerAccountId;
  final bool seedDemoData;
}
