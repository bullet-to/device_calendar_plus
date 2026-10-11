/// Shared helpers for the integration tests. Plain Dart, not a test entry:
/// `all_tests.dart` does not import it.
library;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches a [DeviceCalendarException] carrying [DeviceCalendarError.notFound].
final throwsNotFound = throwsA(isA<DeviceCalendarException>().having(
  (e) => e.errorCode,
  'errorCode',
  DeviceCalendarError.notFound,
));

/// Matches a [DeviceCalendarException] carrying
/// [DeviceCalendarError.invalidArguments]. With [mentioning], the message must
/// also contain it (e.g. the replacement method a refusal points at).
Matcher throwsInvalidArguments({String? mentioning}) {
  var matcher = isA<DeviceCalendarException>().having(
    (e) => e.errorCode,
    'errorCode',
    DeviceCalendarError.invalidArguments,
  );
  if (mentioning != null) {
    matcher = matcher.having((e) => e.message, 'message', contains(mentioning));
  }
  return throwsA(matcher);
}

/// Local midnight [days] calendar days after [day], DST-safe: built from the
/// date rather than by adding 24-hour multiples (or subtracting [day]'s clock
/// time), which land an hour off across a DST transition. The one place that
/// knows how a day offset is built; the helpers below go through it.
DateTime daysOn(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// Local midnight [daysFromNow] days from today, via [daysOn].
DateTime localMidnight(int daysFromNow) => daysOn(DateTime.now(), daysFromNow);

/// Local midnight of [d]'s calendar day, via [daysOn].
DateTime dayOf(DateTime d) => daysOn(d, 0);

/// Local midnight of the calendar day after [day], via [daysOn], so a test
/// that already holds a day can name its end without reading the clock again.
DateTime nextLocalMidnight(DateTime day) => daysOn(day, 1);
