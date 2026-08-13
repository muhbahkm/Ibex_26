import '../errors/domain_error.dart';

abstract interface class BusinessDocumentCalendar {
  int documentYear(DateTime occurredAtUtc);
  DateTime localDateTime(DateTime occurredAtUtc);
}

class FixedOffsetBusinessDocumentCalendar implements BusinessDocumentCalendar {
  const FixedOffsetBusinessDocumentCalendar(this.utcOffsetMinutes)
      : assert(utcOffsetMinutes >= -840 && utcOffsetMinutes <= 840);

  static const utc = FixedOffsetBusinessDocumentCalendar(0);

  final int utcOffsetMinutes;

  factory FixedOffsetBusinessDocumentCalendar.validated(int utcOffsetMinutes) {
    if (utcOffsetMinutes < -840 || utcOffsetMinutes > 840) {
      throw const DomainError(
        'BUSINESS_TIMEZONE_OFFSET_INVALID',
        'Business UTC offset must be within -14:00 and +14:00.',
      );
    }
    return FixedOffsetBusinessDocumentCalendar(utcOffsetMinutes);
  }

  @override
  DateTime localDateTime(DateTime occurredAtUtc) =>
      occurredAtUtc.toUtc().add(Duration(minutes: utcOffsetMinutes));

  @override
  int documentYear(DateTime occurredAtUtc) => localDateTime(occurredAtUtc).year;
}
