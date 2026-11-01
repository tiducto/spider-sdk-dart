import 'errors.dart';

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
  return invalidInput('serviceDate', malformed: true);
}
