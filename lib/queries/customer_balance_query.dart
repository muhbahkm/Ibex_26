import 'package:drift/drift.dart';

import '../database/spike_database.dart';

class CustomerCurrencyBalance {
  const CustomerCurrencyBalance({
    required this.currencyCode,
    required this.balanceScaled,
    required this.baseBalanceScaled,
  });

  final String currencyCode;
  final int balanceScaled;
  final int baseBalanceScaled;
}

class CustomerBalanceQuery {
  const CustomerBalanceQuery(this.db);

  final SpikeDatabase db;

  Future<List<CustomerCurrencyBalance>> execute({
    required String businessId,
    required String customerId,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT currency_code,
             COALESCE(SUM(debit_scaled - credit_scaled), 0) AS balance_scaled,
             COALESCE(SUM(base_debit_scaled - base_credit_scaled), 0) AS base_balance_scaled
      FROM customer_ledger
      WHERE business_id = ? AND customer_id = ?
      GROUP BY currency_code
      ORDER BY currency_code
      ''',
      variables: [
        Variable.withString(businessId),
        Variable.withString(customerId),
      ],
      readsFrom: {db.customerLedger},
    ).get();

    return rows
        .map((row) => CustomerCurrencyBalance(
              currencyCode: row.read<String>('currency_code'),
              balanceScaled: row.read<int>('balance_scaled'),
              baseBalanceScaled: row.read<int>('base_balance_scaled'),
            ))
        .toList(growable: false);
  }
}
