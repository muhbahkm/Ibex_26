import 'package:drift/drift.dart';

import '../core/errors/domain_error.dart';
import '../database/spike_database.dart';

class FxRateSnapshot {
  const FxRateSnapshot({
    required this.rateId,
    required this.fromCurrency,
    required this.toCurrency,
    required this.rateScaled,
    required this.effectiveAt,
  });

  final String rateId;
  final String fromCurrency;
  final String toCurrency;
  final int rateScaled;
  final DateTime effectiveAt;
}

class LocalFxRateProvider {
  const LocalFxRateProvider({required this.db, required this.businessId});

  final SpikeDatabase db;
  final String businessId;

  Future<FxRateSnapshot> resolve({
    required String fromCurrency,
    required String toCurrency,
    required DateTime at,
  }) async {
    final from = _currency(fromCurrency);
    final to = _currency(toCurrency);
    if (from == to) {
      return FxRateSnapshot(
        rateId: 'BASE-$from',
        fromCurrency: from,
        toCurrency: to,
        rateScaled: 100000000,
        effectiveAt: at.toUtc(),
      );
    }

    final row = await (db.select(db.fxRates)
          ..where((r) =>
              r.businessId.equals(businessId) &
              r.fromCurrency.equals(from) &
              r.toCurrency.equals(to) &
              r.active.equals(true) &
              r.effectiveAt.isSmallerOrEqualValue(at.toUtc()))
          ..orderBy([(r) => OrderingTerm.desc(r.effectiveAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) {
      throw DomainError(
        'FX_RATE_NOT_CONFIGURED',
        'No effective FX rate is configured for $from/$to.',
      );
    }
    if (row.rateScaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Configured FX rate must be positive.');
    }
    return FxRateSnapshot(
      rateId: row.id,
      fromCurrency: from,
      toCurrency: to,
      rateScaled: row.rateScaled,
      effectiveAt: row.effectiveAt.toUtc(),
    );
  }

  String _currency(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw const DomainError('FX_CURRENCY_INVALID', 'Currency code must be 3 Latin letters.');
    }
    return normalized;
  }
}
