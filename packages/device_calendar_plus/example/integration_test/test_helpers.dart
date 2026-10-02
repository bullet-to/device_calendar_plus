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

/// Local midnight [daysFromNow] days from today. Built via the constructor
/// rather than `DateTime.add`, so the result is a calendar day rather than
/// 24 hours (which lands an hour off across a DST transition).
DateTime localMidnight(int daysFromNow) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + daysFromNow);
}

/// Local midnight of the calendar day after [day], DST-safe: built from the
/// date rather than by adding 24 hours, so a test that already holds a day
/// can name its end without reading the clock again.
DateTime nextLocalMidnight(DateTime day) =>
    DateTime(day.year, day.month, day.day + 1);

/// Local midnight of the calendar day [d] falls on, DST-safe: built from the
/// date rather than by truncating hours.
DateTime localDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// A local time on [day] whose UTC date isn't [day], where the zone allows
/// one: just after midnight east of UTC, just before it west of UTC (where
/// an hour-long event also runs into the next day). An all-day time read as
/// a UTC date lands a day off here, so it catches that mix-up.
DateTime startOnOtherUtcDate(DateTime day) => day.timeZoneOffset.isNegative
    ? day.add(const Duration(hours: 23, minutes: 30))
    : day.add(const Duration(minutes: 30));
