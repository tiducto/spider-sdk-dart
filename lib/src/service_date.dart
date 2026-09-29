import 'errors.dart';

/// The GTFS service date (ISO `YYYY-MM-DD`) of a stop time whose wire `serviceDay` anchors that day's times.
// `serviceDay` is noon minus 12 h on the service date, so noon's UTC calendar date is the service date in
// any zone within ±12 h of UTC, across DST changes and for after-midnight trips alike.
String serviceDateOf(int serviceDay) {
  final noon = DateTime.fromMillisecondsSinceEpoch((serviceDay + 43200) * 1000,
      isUtc: true);
  String pad(int v, int width) => v.toString().padLeft(width, '0');
  return '${pad(noon.year, 4)}-${pad(noon.month, 2)}-${pad(noon.day, 2)}';
}

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// A [SpiderErrorCode.badRequest] naming `serviceDate` unless [value] is a real calendar date written as ISO
/// `YYYY-MM-DD`; null when it is valid.
SpiderError? invalidServiceDate(String value) {
  final match = _isoDate.firstMatch(value);
  if (match != null) {
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    if (date.year == year && date.month == month && date.day == day) {
      return null;
    }
  }
  return SpiderError(SpiderErrorCode.badRequest,
      'serviceDate must be an ISO-8601 date (YYYY-MM-DD), got "$value"',
      field: 'serviceDate');
}
