import '../errors/domain_error.dart';
import 'scaled_math.dart';

class Quantity {
  const Quantity._(this.scaled);

  static const int scale = 1000000;

  final int scaled;

  factory Quantity.fromScaled(int scaled) => Quantity._(checkedInt64(scaled));

  factory Quantity.parseExact(String text, {required int allowedDecimals}) {
    if (allowedDecimals < 0 || allowedDecimals > 6) {
      throw const DomainError('QTY_UNIT_PRECISION_INVALID', 'Allowed decimals must be between 0 and 6.');
    }
    final value = text.trim();
    if (!containsOnlyLatinNumericSyntax(value)) {
      throw const DomainError('QTY_FORMAT_INVALID', 'Quantity input must use Latin digits and optional decimal point.');
    }
    final negative = value.startsWith('-');
    final unsigned = value.startsWith('-') || value.startsWith('+') ? value.substring(1) : value;
    final parts = unsigned.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > allowedDecimals) {
      throw const DomainError('QTY_PRECISION_EXCEEDED', 'Quantity exceeds unit precision.');
    }
    final whole = int.parse(parts[0]);
    final fractionScaled = fraction.isEmpty ? 0 : int.parse(fraction.padRight(6, '0'));
    final magnitude = checkedInt64(whole * scale + fractionScaled);
    return Quantity.fromScaled(negative ? -magnitude : magnitude);
  }

  Quantity operator +(Quantity other) => Quantity.fromScaled(checkedInt64(scaled + other.scaled));
  Quantity operator -(Quantity other) => Quantity.fromScaled(checkedInt64(scaled - other.scaled));

  bool get isNegative => scaled < 0;
  bool get isZero => scaled == 0;

  @override
  bool operator ==(Object other) => other is Quantity && other.scaled == scaled;

  @override
  int get hashCode => scaled.hashCode;
}
