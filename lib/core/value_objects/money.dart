import '../errors/domain_error.dart';
import 'scaled_math.dart';

class Money {
  const Money._(this.scaled, this.currencyCode);

  static const int scale = 10000;

  final int scaled;
  final String currencyCode;

  factory Money.fromScaled(int scaled, String currencyCode) {
    final normalized = currencyCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw const DomainError('MONEY_CURRENCY_INVALID', 'Currency code must be 3 Latin letters.');
    }
    return Money._(checkedInt64(scaled), normalized);
  }

  factory Money.parseExact(String text, String currencyCode) {
    final value = text.trim();
    if (!containsOnlyLatinNumericSyntax(value)) {
      throw const DomainError('MONEY_FORMAT_INVALID', 'Money input must use Latin digits and optional decimal point.');
    }

    final negative = value.startsWith('-');
    final unsigned = value.startsWith('-') || value.startsWith('+') ? value.substring(1) : value;
    final parts = unsigned.split('.');
    final whole = int.parse(parts[0]);
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > 4) {
      throw const DomainError('MONEY_PRECISION_EXCEEDED', 'Money input exceeds 4 decimal places.');
    }
    final fractionScaled = fraction.isEmpty ? 0 : int.parse(fraction.padRight(4, '0'));
    final magnitude = checkedInt64(whole * scale + fractionScaled);
    return Money.fromScaled(negative ? -magnitude : magnitude, currencyCode);
  }

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money.fromScaled(checkedInt64(scaled + other.scaled), currencyCode);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money.fromScaled(checkedInt64(scaled - other.scaled), currencyCode);
  }

  Money negate() => Money.fromScaled(checkedInt64(-scaled), currencyCode);

  bool get isZero => scaled == 0;
  bool get isNegative => scaled < 0;

  String format({int decimals = 2}) {
    if (decimals < 0 || decimals > 4) {
      throw const DomainError('MONEY_DISPLAY_PRECISION_INVALID', 'Display decimals must be between 0 and 4.');
    }
    final negative = scaled < 0;
    final magnitude = scaled.abs();
    final whole = magnitude ~/ scale;
    final fraction4 = (magnitude % scale).toString().padLeft(4, '0');
    final fraction = decimals == 0 ? '' : '.${fraction4.substring(0, decimals)}';
    return '${negative ? '-' : ''}$whole$fraction';
  }

  void _requireSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw const DomainError('MONEY_CURRENCY_MISMATCH', 'Money operations require the same currency.');
    }
  }

  @override
  bool operator ==(Object other) => other is Money && other.scaled == scaled && other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(scaled, currencyCode);
}
