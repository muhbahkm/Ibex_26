import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/finance/local_fx_rate_provider.dart';

void main() {
  test('latest active effective rate at transaction date wins', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final provider = LocalFxRateProvider(db: db, businessId: 'B-1');
    final createdAt = DateTime.utc(2026, 8, 11);

    for (final rate in [
      (id: 'FX-OLD', effectiveAt: DateTime.utc(2026, 1, 1), scaled: 420 * 100000000),
      (id: 'FX-CURRENT', effectiveAt: DateTime.utc(2026, 6, 1), scaled: 425 * 100000000),
      (id: 'FX-FUTURE', effectiveAt: DateTime.utc(2026, 9, 1), scaled: 430 * 100000000),
    ]) {
      await db.into(db.fxRates).insert(
            FxRatesCompanion.insert(
              id: rate.id,
              businessId: 'B-1',
              fromCurrency: 'SAR',
              toCurrency: 'YER',
              rateScaled: rate.scaled,
              effectiveAt: rate.effectiveAt,
              createdAt: createdAt,
            ),
          );
    }

    final snapshot = await provider.resolve(
      fromCurrency: 'sar',
      toCurrency: 'yer',
      at: DateTime.utc(2026, 8, 11),
    );

    expect(snapshot.rateId, 'FX-CURRENT');
    expect(snapshot.rateScaled, 425 * 100000000);
    expect(snapshot.effectiveAt, DateTime.utc(2026, 6, 1));
  });

  test('inactive rate is ignored and missing effective rate fails closed', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final provider = LocalFxRateProvider(db: db, businessId: 'B-1');
    final now = DateTime.utc(2026, 8, 11);

    await db.into(db.fxRates).insert(
          FxRatesCompanion.insert(
            id: 'FX-INACTIVE',
            businessId: 'B-1',
            fromCurrency: 'USD',
            toCurrency: 'YER',
            rateScaled: 1600 * 100000000,
            effectiveAt: DateTime.utc(2026, 1, 1),
            active: const Value(false),
            createdAt: now,
          ),
        );

    await expectLater(
      provider.resolve(
        fromCurrency: 'USD',
        toCurrency: 'YER',
        at: now,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('same currency resolves exact 1e8 without a configured row', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final provider = LocalFxRateProvider(db: db, businessId: 'B-1');
    final at = DateTime.utc(2026, 8, 11);

    final snapshot = await provider.resolve(
      fromCurrency: 'SAR',
      toCurrency: 'SAR',
      at: at,
    );

    expect(snapshot.rateId, 'BASE-SAR');
    expect(snapshot.rateScaled, 100000000);
    expect(snapshot.effectiveAt, at);
  });
}
