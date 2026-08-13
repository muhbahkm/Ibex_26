import 'package:drift/drift.dart';

import '../core/errors/domain_error.dart';
import '../database/spike_database.dart';

class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountId,
    required this.debitScaled,
    required this.creditScaled,
  });

  final String accountId;
  final int debitScaled;
  final int creditScaled;

  int get netDebitScaled => debitScaled - creditScaled;
}

class TrialBalanceReport {
  const TrialBalanceReport({
    required this.businessId,
    required this.fromInclusive,
    required this.toExclusive,
    required this.rows,
  });

  final String businessId;
  final DateTime fromInclusive;
  final DateTime toExclusive;
  final List<TrialBalanceRow> rows;

  int get totalDebitScaled =>
      rows.fold<int>(0, (sum, row) => sum + row.debitScaled);
  int get totalCreditScaled =>
      rows.fold<int>(0, (sum, row) => sum + row.creditScaled);
  bool get isBalanced => totalDebitScaled == totalCreditScaled;
}

class TrialBalanceQuery {
  const TrialBalanceQuery(this.db);

  final SpikeDatabase db;

  Future<TrialBalanceReport> load({
    required String businessId,
    required DateTime fromInclusive,
    required DateTime toExclusive,
  }) async {
    final business = businessId.trim();
    final from = fromInclusive.toUtc();
    final to = toExclusive.toUtc();
    if (business.isEmpty) {
      throw const DomainError(
        'REPORT_BUSINESS_REQUIRED',
        'Trial balance requires a business scope.',
      );
    }
    if (!to.isAfter(from)) {
      throw const DomainError(
        'REPORT_DATE_RANGE_INVALID',
        'Trial balance end must be after start.',
      );
    }

    final result = await db.customSelect(
      '''
      SELECT
        jl.account_id AS account_id,
        SUM(jl.base_debit_scaled) AS debit_scaled,
        SUM(jl.base_credit_scaled) AS credit_scaled
      FROM journal_lines jl
      INNER JOIN journal_entries je
        ON je.id = jl.journal_entry_id
      WHERE je.business_id = ?
        AND je.status = 'posted'
        AND je.entry_at >= ?
        AND je.entry_at < ?
      GROUP BY jl.account_id
      ORDER BY jl.account_id ASC
      ''',
      variables: [
        Variable.withString(business),
        Variable.withDateTime(from),
        Variable.withDateTime(to),
      ],
      readsFrom: {db.journalEntries, db.journalLines},
    ).get();

    final rows = result
        .map(
          (row) => TrialBalanceRow(
            accountId: row.read<String>('account_id'),
            debitScaled: row.read<int>('debit_scaled'),
            creditScaled: row.read<int>('credit_scaled'),
          ),
        )
        .toList(growable: false);

    return TrialBalanceReport(
      businessId: business,
      fromInclusive: from,
      toExclusive: to,
      rows: rows,
    );
  }
}
