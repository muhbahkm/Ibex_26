import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/scaled_math.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'transfer_stock_command.dart';

class TransferStockService {
  TransferStockService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<TransferStockResult> execute(TransferStockCommand command) async {
    if (command.operationId.trim().isEmpty || command.lines.isEmpty) {
      throw const DomainError('TRANSFER_INPUT_REQUIRED', 'Transfer operation and lines are required.');
    }
    if (command.sourceWarehouseId == command.destinationWarehouseId) {
      throw const DomainError('TRANSFER_WAREHOUSE_SAME', 'Source and destination warehouses must differ.');
    }

    final requiredByProduct = <String, int>{};
    for (final line in command.lines) {
      if (line.productId.trim().isEmpty || line.quantityScaled <= 0) {
        throw const DomainError('TRANSFER_LINE_INVALID', 'Transfer lines require product and positive quantity.');
      }
      requiredByProduct.update(
        line.productId,
        (value) => checkedInt64(value + line.quantityScaled),
        ifAbsent: () => checkedInt64(line.quantityScaled),
      );
    }

    return db.transaction(() async {
      final prior = await (db.select(db.operationLog)
            ..where((row) => row.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (prior != null) {
        final transfer = await (db.select(db.stockTransfers)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (transfer == null) {
          throw const DomainError('OPERATION_STATE_CORRUPT', 'Operation exists without stock transfer truth.');
        }
        return TransferStockResult(
          transferId: transfer.id,
          documentNo: transfer.documentNo,
          sourceMovementId: transfer.sourceMovementId,
          destinationMovementId: transfer.destinationMovementId,
          idempotentReplay: true,
        );
      }

      for (final warehouseId in [command.sourceWarehouseId, command.destinationWarehouseId]) {
        final warehouse = await (db.select(db.warehouses)
              ..where((row) =>
                  row.id.equals(warehouseId) &
                  row.businessId.equals(command.businessId) &
                  row.active.equals(true)))
            .getSingleOrNull();
        if (warehouse == null) {
          throw const DomainError('WAREHOUSE_NOT_FOUND', 'Transfer warehouse is not active in this business.');
        }
      }

      final sourceBalances = <String, InventoryBalance>{};
      for (final entry in requiredByProduct.entries) {
        final balance = await (db.select(db.inventoryBalances)
              ..where((row) =>
                  row.warehouseId.equals(command.sourceWarehouseId) &
                  row.productId.equals(entry.key)))
            .getSingleOrNull();
        if (balance == null || balance.quantityScaled < entry.value) {
          throw const DomainError('INV_INSUFFICIENT_STOCK', 'Insufficient stock for transfer.');
        }
        sourceBalances[entry.key] = balance;
      }

      final transferId = _uuid.v4();
      final outMovementId = _uuid.v4();
      final inMovementId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'stock_transfer',
        year: command.transferredAt.toUtc().year,
        prefix: 'STX',
      );

      await db.into(db.stockTransfers).insert(
            StockTransfersCompanion.insert(
              id: transferId,
              businessId: command.businessId,
              documentNo: documentNo,
              sourceWarehouseId: command.sourceWarehouseId,
              destinationWarehouseId: command.destinationWarehouseId,
              status: 'posted',
              transferredAt: command.transferredAt.toUtc(),
              sourceMovementId: outMovementId,
              destinationMovementId: inMovementId,
              operationId: command.operationId,
            ),
          );

      for (final movement in [
        (id: outMovementId, warehouseId: command.sourceWarehouseId, type: 'TRANSFER_OUT'),
        (id: inMovementId, warehouseId: command.destinationWarehouseId, type: 'TRANSFER_IN'),
      ]) {
        await db.into(db.stockMovements).insert(
              StockMovementsCompanion.insert(
                id: movement.id,
                businessId: command.businessId,
                warehouseId: movement.warehouseId,
                movementType: movement.type,
                referenceType: 'stock_transfer',
                referenceId: transferId,
                status: 'posted',
                movementAt: command.transferredAt.toUtc(),
                operationId: command.operationId,
              ),
            );
      }

      final totalCostByProduct = <String, int>{};
      for (final line in command.lines) {
        final source = sourceBalances[line.productId]!;
        final lineCost = divideHalfAwayFromZero(
          line.quantityScaled * source.wacUnitCostScaled,
          1000000,
        );
        totalCostByProduct.update(
          line.productId,
          (value) => checkedInt64(value + lineCost),
          ifAbsent: () => lineCost,
        );
        await db.into(db.stockTransferItems).insert(
              StockTransferItemsCompanion.insert(
                id: _uuid.v4(),
                transferId: transferId,
                productId: line.productId,
                quantityScaled: line.quantityScaled,
                unitCostScaled: source.wacUnitCostScaled,
                totalCostScaled: lineCost,
              ),
            );
        await db.into(db.stockMovementItems).insert(
              StockMovementItemsCompanion.insert(
                id: _uuid.v4(),
                stockMovementId: outMovementId,
                productId: line.productId,
                quantityScaled: -line.quantityScaled,
                unitCostScaled: source.wacUnitCostScaled,
                totalCostScaled: -lineCost,
              ),
            );
        await db.into(db.stockMovementItems).insert(
              StockMovementItemsCompanion.insert(
                id: _uuid.v4(),
                stockMovementId: inMovementId,
                productId: line.productId,
                quantityScaled: line.quantityScaled,
                unitCostScaled: source.wacUnitCostScaled,
                totalCostScaled: lineCost,
              ),
            );
      }

      for (final entry in requiredByProduct.entries) {
        final productId = entry.key;
        final movedQty = entry.value;
        final movedValue = totalCostByProduct[productId]!;
        final source = sourceBalances[productId]!;
        final sourceQty = checkedInt64(source.quantityScaled - movedQty);
        final sourceValue = checkedInt64(source.inventoryValueScaled - movedValue);
        await (db.update(db.inventoryBalances)
              ..where((row) =>
                  row.warehouseId.equals(command.sourceWarehouseId) &
                  row.productId.equals(productId)))
            .write(
          InventoryBalancesCompanion(
            quantityScaled: Value(sourceQty),
            inventoryValueScaled: Value(sourceValue),
            wacUnitCostScaled: Value(sourceQty == 0 ? 0 : divideHalfAwayFromZero(sourceValue * 1000000, sourceQty)),
            updatedAt: Value(now),
          ),
        );

        final destination = await (db.select(db.inventoryBalances)
              ..where((row) =>
                  row.warehouseId.equals(command.destinationWarehouseId) &
                  row.productId.equals(productId)))
            .getSingleOrNull();
        final destinationQty = checkedInt64((destination?.quantityScaled ?? 0) + movedQty);
        final destinationValue = checkedInt64((destination?.inventoryValueScaled ?? 0) + movedValue);
        final destinationWac = divideHalfAwayFromZero(destinationValue * 1000000, destinationQty);
        if (destination == null) {
          await db.into(db.inventoryBalances).insert(
                InventoryBalancesCompanion.insert(
                  warehouseId: command.destinationWarehouseId,
                  productId: productId,
                  quantityScaled: destinationQty,
                  inventoryValueScaled: destinationValue,
                  wacUnitCostScaled: destinationWac,
                  updatedAt: now,
                ),
              );
        } else {
          await (db.update(db.inventoryBalances)
                ..where((row) =>
                    row.warehouseId.equals(command.destinationWarehouseId) &
                    row.productId.equals(productId)))
              .write(
            InventoryBalancesCompanion(
              quantityScaled: Value(destinationQty),
              inventoryValueScaled: Value(destinationValue),
              wacUnitCostScaled: Value(destinationWac),
              updatedAt: Value(now),
            ),
          );
        }
      }

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'TransferStock',
              entityType: const Value('stock_transfer'),
              entityId: Value(transferId),
              status: 'committed',
              createdAt: now,
            ),
          );
      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'stock_transfer',
              entityId: transferId,
              action: 'TRANSFER_STOCK',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'source_warehouse_id': command.sourceWarehouseId,
                'destination_warehouse_id': command.destinationWarehouseId,
                'line_count': command.lines.length,
              }),
            ),
          );

      return TransferStockResult(
        transferId: transferId,
        documentNo: documentNo,
        sourceMovementId: outMovementId,
        destinationMovementId: inMovementId,
        idempotentReplay: false,
      );
    });
  }
}
