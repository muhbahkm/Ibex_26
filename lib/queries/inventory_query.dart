import 'package:drift/drift.dart';

import '../database/spike_database.dart';

class InventoryBalanceSnapshot {
  const InventoryBalanceSnapshot({
    required this.warehouseId,
    required this.productId,
    required this.quantityScaled,
    required this.inventoryValueScaled,
    required this.wacUnitCostScaled,
  });

  final String warehouseId;
  final String productId;
  final int quantityScaled;
  final int inventoryValueScaled;
  final int wacUnitCostScaled;
}

class InventoryQuery {
  const InventoryQuery(this.db);

  final SpikeDatabase db;

  Future<InventoryBalanceSnapshot?> byProductWarehouse({
    required String productId,
    required String warehouseId,
  }) async {
    final row = await (db.select(db.inventoryBalances)
          ..where((balance) =>
              balance.productId.equals(productId) &
              balance.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    if (row == null) return null;
    return InventoryBalanceSnapshot(
      warehouseId: row.warehouseId,
      productId: row.productId,
      quantityScaled: row.quantityScaled,
      inventoryValueScaled: row.inventoryValueScaled,
      wacUnitCostScaled: row.wacUnitCostScaled,
    );
  }
}
