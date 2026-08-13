import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/ibex_foundation_spike.dart';

void main() {
  group('Money', () {
    test('parses exact Latin-digit values with scale 1e4', () {
      final money = Money.parseExact('123.4500', 'yer');
      expect(money.scaled, 1234500);
      expect(money.currencyCode, 'YER');
      expect(money.format(decimals: 2), '123.45');
    });

    test('rejects Arabic-Indic digits', () {
      expect(
        () => Money.parseExact('١٢.٥', 'YER'),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', 'MONEY_FORMAT_INVALID')),
      );
    });

    test('rejects currency mismatch', () {
      final a = Money.fromScaled(10000, 'YER');
      final b = Money.fromScaled(10000, 'SAR');
      expect(() => a + b, throwsA(isA<DomainError>()));
    });
  });

  group('ExchangeRate', () {
    test('uses half-away-from-zero rounding', () {
      final rate = ExchangeRate.fromScaled(
        scaled: 33333333,
        fromCurrency: 'USD',
        toCurrency: 'YER',
      );
      final converted = rate.convert(Money.fromScaled(1, 'USD'));
      expect(converted.scaled, 0);

      final rateHalf = ExchangeRate.fromScaled(
        scaled: 50000000,
        fromCurrency: 'USD',
        toCurrency: 'YER',
      );
      expect(rateHalf.convert(Money.fromScaled(1, 'USD')).scaled, 1);
      expect(rateHalf.convert(Money.fromScaled(-1, 'USD')).scaled, -1);
    });
  });

  group('Quantity', () {
    test('uses scale 1e6 and enforces unit precision', () {
      expect(Quantity.parseExact('1.125', allowedDecimals: 3).scaled, 1125000);
      expect(
        () => Quantity.parseExact('1.1251', allowedDecimals: 3),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', 'QTY_PRECISION_EXCEEDED')),
      );
    });
  });

  group('Document number', () {
    test('formats canonical Latin-digit sequence', () {
      expect(
        DocumentNumberFormatter.format(prefix: 'sal', year: 2026, sequence: 1),
        'SAL-2026-000001',
      );
    });
  });
}
