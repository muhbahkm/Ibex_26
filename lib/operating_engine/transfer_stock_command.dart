class TransferStockLineInput {
  const TransferStockLineInput({
    required this.productId,
    required this.quantityScaled,
  });

  final String productId;
  final int quantityScaled;
}

class TransferStockCommand {
  const TransferStockCommand({
    required this.operationId,
    required this.businessId,
    required this.userId,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.transferredAt,
    required this.lines,
  });

  final String operationId;
  final String businessId;
  final String userId;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final DateTime transferredAt;
  final List<TransferStockLineInput> lines;
}

class TransferStockResult {
  const TransferStockResult({
    required this.transferId,
    required this.documentNo,
    required this.sourceMovementId,
    required this.destinationMovementId,
    required this.idempotentReplay,
  });

  final String transferId;
  final String documentNo;
  final String sourceMovementId;
  final String destinationMovementId;
  final bool idempotentReplay;
}
