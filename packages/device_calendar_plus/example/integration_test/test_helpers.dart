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
