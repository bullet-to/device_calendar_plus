import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// `listEvents` contract tests: wide-range chunking
/// (builttoroam/device_calendar#452) and all-day events in sub-day windows.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Regression tests for builttoroam/device_calendar#452.
  //
  // iOS EventKit's `predicateForEvents` silently truncates a date range longer
  // than ~4 years to the first 4 years, so a naive single query drops the later
  // events. The fix chunks wide ranges into <=3-year windows and merges the
  // results — which must return every event exactly once, in start-date
  // order, even for recurring series whose occurrences straddle a window
  // boundary.
  //
  // Android has no such limit, so these also serve as a cross-platform
  // contract.
  group('listEvents wide range (>4 year span)', () {
    late DeviceCalendar plugin;
    String? calendarId;

    // Anchored near "now" (not far-future): EventKit only expands recurring
    // occurrences within a horizon around the present, so a series decades out
    // would return only its master instance. A dedicated calendar + id/title
    // filtering keeps these isolated from anything already on the device.
    final base = DateTime.now().toUtc().add(const Duration(days: 2));
    final queryStart = base.subtract(const Duration(days: 1));
    final queryEnd = base.add(const Duration(days: 3000)); // ~8.2 years

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();
      calendarId = await plugin.createCalendar(
        name: 'Range Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#00AAFF',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    test('returns every event across a span longer than 4 years, once, sorted',
        () async {
      // 10 events from year 0 to ~7.4, including one at exactly +4 years (1461
      // days, leap-adjusted) to stress the window boundary. Created in
      // scrambled order so a sorted result isn't just an artifact of insertion.
      const dayOffsets = [600, 2700, 0, 1461, 900, 2100, 300, 1800, 1200, 2400];
      final expectedTitles = <String>{};
      for (final offset in dayOffsets) {
        final start = base.add(Duration(days: offset));
        final title = 'range-evt-$offset';
        expectedTitles.add(title);
        await plugin.createEvent(
          calendarId: calendarId!,
          title: title,
          startDate: start,
          endDate: start.add(const Duration(hours: 1)),
          timeZone: 'UTC',
        );
      }

      final events = await plugin.listEvents(
        queryStart,
        queryEnd,
        calendarIds: [calendarId!],
      );
      final ours = events.where((e) => expectedTitles.contains(e.title)).toList();

      // Coverage: every created event comes back (the core #452 bug — later
      // events were dropped by the 4-year truncation).
      final returnedTitles = ours.map((e) => e.title).toSet();
      expect(
        returnedTitles,
        containsAll(expectedTitles),
        reason: 'missing events: ${expectedTitles.difference(returnedTitles)}',
      );

      // Dedup: chunked windows must not double-count an event near a boundary.
      final instanceIds = ours.map((e) => e.instanceId).toList();
      expect(
        instanceIds.length,
        instanceIds.toSet().length,
        reason: 'duplicate instanceIds returned across windows',
      );
      expect(ours.length, dayOffsets.length);

      // Ordering: listEvents promises start-date order across all windows.
      for (var i = 1; i < ours.length; i++) {
        expect(
          ours[i].startDate.isBefore(ours[i - 1].startDate),
          isFalse,
          reason: 'events not sorted by start date at index $i',
        );
      }
    });

    test('does not duplicate recurring instances across window boundaries',
        () async {
      // 42 monthly occurrences => 3.5-year span, crossing the internal ~3-year
      // window boundary while staying within EventKit's recurrence-expansion
      // horizon. Each occurrence must appear exactly once.
      const occurrenceCount = 42;
      final start = base.add(const Duration(days: 5));
      final recurringId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'monthly-series',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: MonthlyRecurrence(end: CountEnd(occurrenceCount)),
        timeZone: 'UTC',
      );

      final events = await plugin.listEvents(
        queryStart,
        queryEnd,
        calendarIds: [calendarId!],
      );
      final occurrences =
          events.where((e) => e.eventId == recurringId).toList();
      final instanceIds = occurrences.map((e) => e.instanceId).toList();

      expect(
        instanceIds.length,
        instanceIds.toSet().length,
        reason: 'recurring instances duplicated across window boundary',
      );
      expect(
        occurrences.length,
        occurrenceCount,
        reason: 'expected all $occurrenceCount monthly occurrences across the '
            'span (crossing a window boundary)',
      );
    });
  });

  group('listEvents all-day events', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();
      calendarId = await plugin.createCalendar(
        name: 'All-day Window Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#FF8800',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    // iOS EventKit's overlap predicate returns an all-day event for any window
    // that touches its date, however short. Android stores all-day events at
    // UTC midnight and compares them against the window's local dates, so a
    // window that starts and ends on the same date must still count as
    // covering that whole date rather than collapsing to nothing. The
    // neighbouring days pin the other side: widening the window to its date
    // must not pull in the day before or after.
    test('includes an all-day event when the window is a sub-day slice of its '
        'date', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final now = DateTime.now();
      // Local midnight via the constructor, not `add(Duration(days: 3))`: a
      // calendar day, not 24h, so it stays at midnight across a DST change.
      final day = DateTime(now.year, now.month, now.day + 3);
      const dayOffsets = <String, int>{
        'all-day before': -1,
        'all-day on day': 0,
        'all-day after': 1,
      };
      for (final entry in dayOffsets.entries) {
        final start = DateTime(day.year, day.month, day.day + entry.value);
        await plugin.createEvent(
          calendarId: calendarId!,
          title: entry.key,
          startDate: start,
          endDate: DateTime(start.year, start.month, start.day + 1),
          isAllDay: true,
        );
      }

      final events = await plugin.listEvents(
        day.add(const Duration(hours: 10)),
        day.add(const Duration(hours: 11)),
        calendarIds: [calendarId!],
      );

      expect(
        events.map((e) => e.title).where(dayOffsets.containsKey).toList(),
        ['all-day on day'],
        reason:
            "a window inside a date must return that date's all-day event "
            'and nothing from the neighbouring dates',
      );
    });
  });
}
