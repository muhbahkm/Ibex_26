import 'package:drift/drift.dart';

import '../database/spike_database.dart';

class SupplierCurrencyBalance {
  const SupplierCurrencyBalance({
    required this.currencyCode,
    required this.balanceScaled,
    required this.baseBalanceScaled,
  });

  final String currencyCode;
  final int balanceScaled;
  final int baseBalanceScaled;
}

class SupplierBalanceQuery {
  const SupplierBalanceQuery(this.db);

  final SpikeDatabase db;

  Future<List<SupplierCurrencyBalance>> bySupplier({
    required String businessId,
    required String supplierId,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT currency_code,
             SUM(credit_scaled - debit_scaled) AS balance_scaled,
             SUM(base_credit_scaled - base_debit_scaled) AS base_balance_scaled
      FROM supplier_ledger
      WHERE business_id = ? AND supplier_id = ?
      GROUP BY currency_code
      HAVING SUM(credit_scaled - debit_scaled) <> 0
      ORDER BY currency_code
      ''',
      variables: [Variable.withString(businessId), Variable.withString(supplierId)],
      readsFrom: {db.supplierLedger},
    ).get();
    return rows
        .map((row) => SupplierCurrencyBalance(
              currencyCode: row.read<String>('currency_code'),
              balanceScaled: row.read<int>('balance_scaled'),
              baseBalanceScaled: row.read<int>('base_balance_scaled'),
            ))
        .toList(growable: false);
  }
}
