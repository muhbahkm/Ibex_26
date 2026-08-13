import '../errors/domain_error.dart';

class DocumentNumberFormatter {
  const DocumentNumberFormatter._();

  static String format({
    required String prefix,
    required int year,
    required int sequence,
    int padding = 6,
  }) {
    final normalizedPrefix = prefix.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2,8}$').hasMatch(normalizedPrefix)) {
      throw const DomainError('DOC_PREFIX_INVALID', 'Document prefix must use 2-8 Latin letters.');
    }
    if (year < 2000 || year > 9999) {
      throw const DomainError('DOC_SCOPE_INVALID', 'Document year is outside the supported range.');
    }
    if (sequence <= 0) {
      throw const DomainError('DOC_SEQUENCE_INVALID', 'Document sequence must be positive.');
    }
    if (padding < 1 || padding > 12) {
      throw const DomainError('DOC_PADDING_INVALID', 'Document padding must be between 1 and 12.');
    }

    return '$normalizedPrefix-$year-${sequence.toString().padLeft(padding, '0')}';
  }
}
