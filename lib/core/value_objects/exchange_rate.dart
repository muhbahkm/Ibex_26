import '../errors/domain_error.dart';
import 'money.dart';
import 'scaled_math.dart';

class ExchangeRate {
  const ExchangeRate._(this.scaled, this.fromCurrency, this.toCurrency);

  static const int scale = 100000000;

  final int scaled;
  final String fromCurrency;
  final String toCurrency;

  factory ExchangeRate.fromScaled({
    required int scaled,
    required String fromCurrency,
    required String toCurrency,
  }) {
    if (scaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Exchange rate must be positive.');
    }
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(from) || !RegExp(r'^[A-Z]{3}$').hasMatch(to)) {
      throw const DomainError('FX_CURRENCY_INVALID', 'Currency codes must be 3 Latin letters.');
    }
    return ExchangeRate._(checkedInt64(scaled), from, to);
  }

  Money convert(Money source) {
    if (source.currencyCode != fromCurrency) {
      throw const DomainError('FX_SOURCE_CURRENCY_MISMATCH', 'Source money does not match exchange-rate source currency.');
    }
    final convertedScaled = divideHalfAwayFromZero(source.scaled * scaled, scale);
    return Money.fromScaled(checkedInt64(convertedScaled), toCurrency);
  }
}
