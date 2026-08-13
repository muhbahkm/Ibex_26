import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';
import 'package:ibex_foundation_spike/core/time/business_document_calendar.dart';

void main() {
  test('UTC+3 assigns near-midnight UTC document to next local year', () {
    const calendar = FixedOffsetBusinessDocumentCalendar(180);
    final occurredAt = DateTime.utc(2026, 12, 31, 22, 30);

    expect(calendar.localDateTime(occurredAt), DateTime.utc(2027, 1, 1, 1, 30));
    expect(calendar.documentYear(occurredAt), 2027);
  });

  test('UTC-5 assigns early UTC document to previous local year', () {
    const calendar = FixedOffsetBusinessDocumentCalendar(-300);
    final occurredAt = DateTime.utc(2027, 1, 1, 2, 0);

    expect(calendar.documentYear(occurredAt), 2026);
  });

  test('invalid business UTC offset is rejected', () {
    expect(
      () => FixedOffsetBusinessDocumentCalendar.validated(841),
      throwsA(isA<DomainError>().having(
        (error) => error.code,
        'code',
        'BUSINESS_TIMEZONE_OFFSET_INVALID',
      )),
    );
  });
}
