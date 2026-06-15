import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Device probes for upstream edge cases that couldn't be decided by reading
/// the code (builttoroam/device_calendar #416).
///
/// These run the real Dart -> channel -> native -> provider roundtrip on both
/// platforms. A failure here is a reproduced bug to fix; a pass is evidence the
/// case doesn't affect this plugin.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DeviceCalendar plugin;
  String? calendarId;

  // Anchored a few days out from "now" so timed events sit comfortably inside
  // a sane query window regardless of the device clock/timezone.
  DateTime utcMidnightToday() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  setUpAll(() async {
    plugin = DeviceCalendar.instance;
    await plugin.requestPermissions();
    calendarId = await plugin.createCalendar(
      name: 'Edge Test ${DateTime.now().millisecondsSinceEpoch}',
      colorHex: '#FF8800',
    );
  });

  tearDownAll(() async {
    if (calendarId != null) {
      await plugin.deleteCalendar(calendarId!);
    }
  });

  group('listEvents zero-duration timed event (#416)', () {
    test('returns a zero-duration timed event that falls inside the range',
        () async {
      // Non-all-day event with start == end, at midnight UTC, well inside the
      // query window. Probes whether the provider materialises a zero-duration
      // instance at all (independent of the boundary filter).
      final at = utcMidnightToday().add(const Duration(days: 2));
      final id = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'zero-dur-inside',
        startDate: at,
        endDate: at, // zero duration
        timeZone: 'UTC',
      );

      final events = await plugin.listEvents(
        at.subtract(const Duration(days: 1)),
        at.add(const Duration(days: 1)),
        calendarIds: [calendarId!],
      );

      expect(
        events.any((e) => e.eventId == id || e.title == 'zero-dur-inside'),
        isTrue,
        reason: 'zero-duration timed event inside the range was dropped',
      );
    });

    test('returns a zero-duration event sitting exactly on the query start',
        () async {
      // The boundary the strict open-interval filter
      // (eventEnd > startMillis && eventBegin < endMillis) would exclude:
      // begin == end == queryStart. A caller querying [start, end] reasonably
      // expects an event at exactly `start` to appear.
      final at = utcMidnightToday().add(const Duration(days: 4));
      final id = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'zero-dur-boundary',
        startDate: at,
        endDate: at,
        timeZone: 'UTC',
      );

      final events = await plugin.listEvents(
        at, // query starts exactly at the event instant
        at.add(const Duration(days: 1)),
        calendarIds: [calendarId!],
      );

      expect(
        events.any((e) => e.eventId == id || e.title == 'zero-dur-boundary'),
        isTrue,
        reason: 'zero-duration event exactly at query start was excluded by the '
            'strict open-interval overlap filter',
      );
    });
  });
}
