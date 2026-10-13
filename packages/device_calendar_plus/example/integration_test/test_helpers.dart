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

/// Local midnight [days] calendar days after [day]'s local date, DST-safe:
/// built from the date rather than by adding 24-hour multiples (or
/// subtracting [day]'s clock time), which land an hour off across a DST
/// transition. [day] is read in local time whatever frame it arrives in, so
/// a UTC instant can't name the wrong local day. The one place that knows
/// how a day offset is built; the helpers below go through it.
DateTime daysOn(DateTime day, int days) {
  final local = day.toLocal();
  return DateTime(local.year, local.month, local.day + days);
}

/// Local midnight [daysFromNow] days from today, via [daysOn].
DateTime localMidnight(int daysFromNow) => daysOn(DateTime.now(), daysFromNow);

/// Local midnight of the calendar day [d] falls on, via [daysOn].
DateTime localDay(DateTime d) => daysOn(d, 0);

/// Local midnight of the calendar day after [day], via [daysOn], so a test
/// that already holds a day can name its end without reading the clock again.
DateTime nextLocalMidnight(DateTime day) => daysOn(day, 1);

/// A local time on [day] whose UTC date isn't [day], where the zone allows
/// one: just after midnight east of UTC, just before it west of UTC (where
/// an hour-long event also runs into the next day). An all-day time read as
/// a UTC date lands a day off here, so it catches that mix-up.
DateTime startOnOtherUtcDate(DateTime day) => day.timeZoneOffset.isNegative
    ? day.add(const Duration(hours: 23, minutes: 30))
    : day.add(const Duration(minutes: 30));
