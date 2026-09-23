import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Regression tests for the Android read-path bugs from the #121 endpoint
/// audit (#122). Each ran cleanly on iOS before the fix, so iOS is the
/// contract; the tests run on both platforms to keep it that way.
///
/// All-day events are the common thread: Android stores them at UTC midnight
/// and the plugin rewrites them to local midnight on the way out, and each bug
/// is a place where that rewrite was skipped, or applied to the wrong side of
/// a comparison.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DeviceCalendar plugin;
  String? calendarId;

  /// Local midnight [daysFromNow] days from today.
  DateTime localMidnight(int daysFromNow) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + daysFromNow);
  }

  /// The occurrences of [eventId] in the window starting a day before [start],
  /// in the order listEvents returned them.
  Future<List<Event>> occurrencesOf(String eventId, DateTime start) async {
    final events = await plugin.listEvents(
      start.subtract(const Duration(days: 1)),
      start.add(const Duration(days: 10)),
      calendarIds: [calendarId!],
    );
    return events.where((e) => e.eventId == eventId).toList();
  }

  setUpAll(() async {
    plugin = DeviceCalendar.instance;
    await plugin.requestPermissions();
    calendarId = await plugin.createCalendar(
      name: 'Read Path Test ${DateTime.now().millisecondsSinceEpoch}',
      colorHex: '#3366FF',
    );
  });

  tearDownAll(() async {
    if (calendarId != null) {
      await plugin.deleteCalendar(calendarId!);
    }
  });

  group('getEvent with an instance ID (#122)', () {
    // The ID listEvents hands out for an all-day occurrence is the raw UTC
    // midnight it is stored at. Resolving it used to run that instant through
    // the all-day range filter with a two-second window, which collapses to
    // an empty date range in every timezone — so the lookup always missed.
    test('resolves an all-day recurring occurrence', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final start = localMidnight(1);
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'All-day daily',
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
        isAllDay: true,
        recurrenceRule: const DailyRecurrence(end: CountEnd(4)),
      );

      final occurrences = await occurrencesOf(eventId, start);
      expect(occurrences.length, 4,
          reason: 'the series must expand to every occurrence');

      for (final occurrence in occurrences) {
        final fetched = await plugin.getEvent(occurrence.instanceId);
        expect(fetched, isNotNull,
            reason: 'getEvent must resolve the instance ID listEvents '
                'returned (${occurrence.instanceId})');
        expect(fetched!.instanceId, occurrence.instanceId);
        expect(fetched.isAllDay, isTrue);
        expect(fetched.startDate, occurrence.startDate);
        expect(fetched.endDate, occurrence.endDate);
      }
    });

    test('resolves a timed recurring occurrence', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Timed daily',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: const DailyRecurrence(end: CountEnd(4)),
        timeZone: 'UTC',
      );

      final occurrences = await occurrencesOf(eventId, start);
      expect(occurrences.length, 4,
          reason: 'the series must expand to every occurrence');

      final target = occurrences[2];
      final fetched = await plugin.getEvent(target.instanceId);
      expect(fetched, isNotNull,
          reason: 'getEvent must resolve the instance ID listEvents returned');
      expect(fetched!.instanceId, target.instanceId);
      expect(fetched.startDate, target.startDate);
      expect(fetched.endDate, target.endDate);
    });
  });

  group('getEvent with a bare recurring ID (#122)', () {
    // Android stores a recurring master as DTSTART + DURATION with no DTEND.
    // The master read used to take DTEND only, so the end fell back to the
    // start and every recurring master came back zero-length.
    test('returns the master with its real end date', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Timed master',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: const DailyRecurrence(end: CountEnd(3)),
        timeZone: 'UTC',
      );

      final master = await plugin.getEvent(eventId);
      expect(master, isNotNull);
      expect(master!.isRecurring, isTrue);
      expect(master.endDate.difference(master.startDate),
          const Duration(hours: 1),
          reason: 'the master must carry the series duration, not a '
              'zero-length end');
    });

    test('returns an all-day master ending at the next local midnight',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final start = localMidnight(1);
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'All-day master',
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
        isAllDay: true,
        recurrenceRule: const DailyRecurrence(end: CountEnd(3)),
      );

      final master = await plugin.getEvent(eventId);
      expect(master, isNotNull);
      expect(master!.isAllDay, isTrue);
      expect(master.startDate, start);
      expect(master.endDate, localMidnight(2),
          reason: 'an all-day master spans its day, ending at the next '
              'local midnight');
    });
  });

  group('listEvents ordering (#122)', () {
    // An all-day event's stored instant (UTC midnight) and its reported start
    // (local midnight) differ by the zone offset, so sorting on the stored
    // instant puts it on the wrong side of any timed event that falls
    // between the two. The timed events here bracket local midnight from
    // -4h to +8h, so in every non-UTC zone at least one of them sits in that
    // gap and exposes a sort on the raw instant. (In UTC the two instants
    // coincide and the order is right either way.)
    test('sorts all-day events by their local-midnight start', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final day = localMidnight(3);
      await plugin.createEvent(
        calendarId: calendarId!,
        title: 'all-day',
        startDate: day,
        endDate: day.add(const Duration(days: 1)),
        isAllDay: true,
      );
      const timedOffsets = <String, Duration>{
        'timed -4h': Duration(hours: -4),
        'timed -30m': Duration(minutes: -30),
        'timed +30m': Duration(minutes: 30),
        'timed +8h': Duration(hours: 8),
      };
      for (final entry in timedOffsets.entries) {
        final start = day.add(entry.value);
        await plugin.createEvent(
          calendarId: calendarId!,
          title: entry.key,
          startDate: start,
          endDate: start.add(const Duration(minutes: 30)),
        );
      }

      // The calendar is shared with the other groups, so keep only this
      // test's events; a global sort is still a sort on any subset.
      final ours = {'all-day', ...timedOffsets.keys};
      final events = await plugin.listEvents(
        day.subtract(const Duration(days: 1)),
        day.add(const Duration(days: 2)),
        calendarIds: [calendarId!],
      );

      expect(
        events.map((e) => e.title).where(ours.contains).toList(),
        ['timed -4h', 'timed -30m', 'all-day', 'timed +30m', 'timed +8h'],
        reason: 'listEvents must order by the start date it reports, so an '
            'all-day event sits at its local midnight among the timed ones',
      );
    });
  });
}
