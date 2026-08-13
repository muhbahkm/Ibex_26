import '../errors/domain_error.dart';

const int int64Min = -9223372036854775808;
const int int64Max = 9223372036854775807;

int checkedInt64(int value, {String code = 'NUM_OVERFLOW'}) {
  if (value < int64Min || value > int64Max) {
    throw DomainError(code, 'Value exceeds signed Int64 range.');
  }
  return value;
}

int divideHalfAwayFromZero(int numerator, int denominator) {
  if (denominator == 0) {
    throw const DomainError('NUM_DIVIDE_BY_ZERO', 'Division by zero.');
  }

  final negative = (numerator < 0) != (denominator < 0);
  final n = numerator.abs();
  final d = denominator.abs();
  final quotient = n ~/ d;
  final remainder = n % d;
  final roundedMagnitude = remainder * 2 >= d ? quotient + 1 : quotient;
  return negative ? -roundedMagnitude : roundedMagnitude;
}

bool containsOnlyLatinNumericSyntax(String value) {
  return RegExp(r'^[-+]?[0-9]+(?:\.[0-9]+)?$').hasMatch(value);
}
