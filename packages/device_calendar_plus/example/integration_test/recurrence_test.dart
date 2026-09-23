import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Set by `run_integration_tests.sh` when the target is an Android emulator.
/// The emulator's Calendar Provider permanently drops a recurring series'
/// instances after a CONTENT_EXCEPTION_URI insert (verified: 10 occurrences
/// before the insert, then 0 for 10s of polling — it never recovers), which
/// breaks the per-instance edit/delete tests below. The behaviour is correct
/// on physical Android devices and iOS, so those run the tests; only the
/// emulator skips. See builttoroam/device_calendar#416 follow-up.
const bool _isAndroidEmulator = bool.fromEnvironment('DC_ANDROID_EMULATOR');

/// Creates a daily recurring event starting one hour from now (UTC), with
/// `count` total occurrences. Returns the event ID and the start time.
Future<({String eventId, DateTime start})> createDailySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 10,
}) async {
  final start = DateTime.now().add(const Duration(hours: 1));
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: 'Daily Series',
    startDate: start,
    endDate: start.add(const Duration(hours: 1)),
    recurrenceRule: DailyRecurrence(end: CountEnd(count)),
    timeZone: 'UTC',
  );
  return (eventId: eventId, start: start);
}

/// Local midnight [daysFromNow] days from today. Built via the constructor
/// rather than `DateTime.add`, so the result is a calendar day rather than
/// 24 hours (which lands an hour off across a DST transition).
DateTime localMidnight(int daysFromNow) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + daysFromNow);
}

/// Creates an all-day daily recurring event starting tomorrow (local
/// midnight), with `count` total occurrences. Returns the event ID, the start
/// and the end of the first day (the next local midnight, DST-safe).
Future<({String eventId, DateTime start, DateTime end})>
    createAllDayDailySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 10,
}) async {
  final start = localMidnight(1);
  final end = localMidnight(2);
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: 'All-day Daily Series',
    startDate: start,
    endDate: end,
    isAllDay: true,
    recurrenceRule: DailyRecurrence(end: CountEnd(count)),
  );
  return (eventId: eventId, start: start, end: end);
}

/// Creates a weekly recurring event starting at [start] (one hour from now
/// by default, stored in UTC), with `count` weekly occurrences. The recurring
/// weekday is the start's weekday unless [daysOfWeek] is given. Returns the
/// event ID and the start time.
Future<({String eventId, DateTime start})> createWeeklySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 5,
  List<DayOfWeek>? daysOfWeek,
  DateTime? start,
}) async {
  start ??= DateTime.now().add(const Duration(hours: 1));
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: 'Weekly Series',
    startDate: start,
    endDate: start.add(const Duration(hours: 1)),
    recurrenceRule:
        WeeklyRecurrence(daysOfWeek: daysOfWeek, end: CountEnd(count)),
    timeZone: 'UTC',
  );
  return (eventId: eventId, start: start);
}

/// The [DayOfWeek] of [d]: `DateTime.weekday` is 1-based from Monday, as
/// [DayOfWeek.values] is 0-based from Monday.
DayOfWeek weekdayOf(DateTime d) => DayOfWeek.values[d.weekday - 1];

/// Creates a weekly series pinned (BYDAY) to its own start weekday, for the
/// #140 tests that then switch it to [newDay], the weekday after. The series
/// is stored in UTC, so both weekdays are derived in UTC — a device-local
/// read flakes whenever local and UTC dates differ (#103). The start and the
/// pinned weekday come from the one instant, so they can't straddle a UTC
/// midnight.
Future<({String eventId, DateTime start, DayOfWeek newDay})>
    createWeeklySeriesOnOwnWeekday(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 6,
}) async {
  final anchor = DateTime.now().toUtc().add(const Duration(hours: 1));
  final series = await createWeeklySeries(plugin, calendarId,
      count: count, daysOfWeek: [weekdayOf(anchor)], start: anchor);
  return (
    eventId: series.eventId,
    start: series.start,
    newDay: weekdayOf(anchor.add(const Duration(days: 1))),
  );
}

/// Asserts [occurrences] is the series a rule switch to weekday [on] leaves
/// (#140): exactly [count] of them, every one on [on], the first at
/// [firstAt] (the day after the old anchor), and none at [orphanAt] — the
/// old anchor, which must not survive as an extra occurrence. Timed series
/// are read in UTC, their stored frame (#103); all-day ones in local time.
void expectReanchoredWeekly(
  List<Event> occurrences, {
  required DayOfWeek on,
  required DateTime firstAt,
  required DateTime orphanAt,
  int count = 3,
  bool allDay = false,
}) {
  expect(occurrences.length, count,
      reason: 'the series must expand to every occurrence the rule '
          'generates before its end');
  expect(
    occurrences.first.startDate.millisecondsSinceEpoch,
    firstAt.millisecondsSinceEpoch,
    reason: 'the anchor must move to the first day the new rule generates',
  );
  expect(
    occurrences.every((e) =>
        (allDay ? e.startDate : e.startDate.toUtc()).weekday == on.index + 1),
    isTrue,
    reason: 'every occurrence must fall on the new weekday',
  );
  expect(
    occurrences.where((e) =>
        e.startDate.millisecondsSinceEpoch == orphanAt.millisecondsSinceEpoch),
    isEmpty,
    reason: 'the old anchor must not survive on the old weekday as an '
        'orphan (#140)',
  );
  if (allDay) {
    expect(occurrences.every((e) => e.isAllDay), isTrue,
        reason: 'the series must stay all-day');
  }
}

/// Asserts [remaining] is what a `thisAndFollowing` split leaves on the
/// original series: exactly [count] occurrences, every one before the split
/// at [before]. The split occurrence itself must not survive here (#140).
void expectTruncatedMaster(
  List<Event> remaining, {
  required DateTime before,
  int count = 2,
}) {
  expect(remaining.length, count,
      reason: 'only the occurrences before the split stay on the original '
          'series');
  expect(
    remaining.every((e) => e.startDate.isBefore(before)),
    isTrue,
    reason: 'the original series must not extend past the split point '
        '(#140)',
  );
}

/// Lists the occurrences of `eventId` in the calendar over a window wide
/// enough to capture the whole series ([windowDays] forward), in date order
/// as returned by the platform.
Future<List<Event>> occurrencesOf(
  DeviceCalendar plugin,
  String calendarId,
  String eventId,
  DateTime start, {
  int windowDays = 14,
}) async {
  final events = await plugin.listEvents(
    start.subtract(const Duration(days: 1)),
    start.add(Duration(days: windowDays)),
    calendarIds: [calendarId],
  );
  return events.where((e) => e.eventId == eventId).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Recurrence Roundtrip Tests', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      // Create a test calendar
      calendarId = await plugin.createCalendar(
        name: 'Recurrence Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#FF0000',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    /// Helper: create event, read it back by ID, return the recurrence rule.
    Future<RecurrenceRule?> roundtrip(
      RecurrenceRule rule, {
      String title = 'Test Event',
      String? timeZone,
    }) async {
      final start = DateTime.now().add(const Duration(hours: 1));
      final end = start.add(const Duration(hours: 1));

      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: title,
        startDate: start,
        endDate: end,
        isAllDay: false,
        recurrenceRule: rule,
        timeZone: timeZone ?? 'UTC',
      );

      expect(eventId, isNotNull);
      expect(eventId, isNotEmpty);

      final event = await plugin.getEvent(eventId);
      expect(event, isNotNull, reason: 'Event should be retrievable by ID');
      expect(event!.isRecurring, isTrue, reason: 'Event should be recurring');

      return event.recurrenceRule;
    }

    // -- Frequency roundtrips --

    test('Daily recurrence roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final rule = roundtrip(const DailyRecurrence(end: CountEnd(5)));
      final result = await rule;

      expect(result, isNotNull);
      expect(result, isA<DailyRecurrence>());
      expect((result!.end as CountEnd).count, 5);
    });

    test('Weekly recurrence roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(const WeeklyRecurrence(
        daysOfWeek: [DayOfWeek.monday, DayOfWeek.wednesday, DayOfWeek.friday],
        end: CountEnd(10),
      ));

      expect(result, isNotNull);
      expect(result, isA<WeeklyRecurrence>());
      final weekly = result as WeeklyRecurrence;
      expect(weekly.daysOfWeek, isNotNull);
      expect(weekly.daysOfWeek!.length, 3);
      expect(weekly.daysOfWeek!, contains(DayOfWeek.monday));
      expect(weekly.daysOfWeek!, contains(DayOfWeek.wednesday));
      expect(weekly.daysOfWeek!, contains(DayOfWeek.friday));
      expect((weekly.end as CountEnd).count, 10);
    });

    test('Monthly recurrence with BYMONTHDAY roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(MonthlyRecurrence(
        daysOfMonth: [15],
        end: CountEnd(12),
      ));

      expect(result, isNotNull);
      expect(result, isA<MonthlyByDate>());
      final monthly = result as MonthlyByDate;
      expect(monthly.daysOfMonth, [15]);
      expect((monthly.end as CountEnd).count, 12);
    });

    test('Yearly recurrence roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(YearlyRecurrence(
        end: CountEnd(5),
      ));

      expect(result, isNotNull);
      expect(result, isA<YearlyByDate>());
      expect((result!.end as CountEnd).count, 5);
    });

    test('Monthly by weekday - 2nd Tuesday roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
        end: CountEnd(6),
      ));

      expect(result, isNotNull);
      expect(result, isA<MonthlyByWeekday>());
      final monthly = result as MonthlyByWeekday;
      expect(monthly.daysOfWeek.length, 1);
      expect(monthly.daysOfWeek[0].day, DayOfWeek.tuesday);
      expect(monthly.daysOfWeek[0].position, 2);
      expect((monthly.end as CountEnd).count, 6);
    });

    test('Monthly with multiple BYMONTHDAY roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(MonthlyRecurrence(
        daysOfMonth: [1, 15],
        end: CountEnd(12),
      ));

      expect(result, isNotNull);
      expect(result, isA<MonthlyByDate>());
      final monthly = result as MonthlyByDate;
      expect(monthly.daysOfMonth, isNotNull);
      expect(monthly.daysOfMonth!.length, 2);
      expect(monthly.daysOfMonth!, contains(1));
      expect(monthly.daysOfMonth!, contains(15));
    });

    test('Yearly by weekday - 4th Thursday of November roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(YearlyRecurrence.byWeekday(
        months: [11],
        daysOfWeek: [RecurrenceDay(DayOfWeek.thursday, position: 4)],
        end: CountEnd(5),
      ));

      expect(result, isNotNull);
      expect(result, isA<YearlyByWeekday>());
      final yearly = result as YearlyByWeekday;
      expect(yearly.months, [11]);
      expect(yearly.daysOfWeek.length, 1);
      expect(yearly.daysOfWeek[0].day, DayOfWeek.thursday);
      expect(yearly.daysOfWeek[0].position, 4);
    });

    test('Yearly with multiple months roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(YearlyRecurrence(
        months: [6, 12],
        daysOfMonth: [15],
        end: CountEnd(10),
      ));

      expect(result, isNotNull);
      expect(result, isA<YearlyByDate>());
      final yearly = result as YearlyByDate;
      expect(yearly.months, isNotNull);
      expect(yearly.months!.length, 2);
      expect(yearly.months!, contains(6));
      expect(yearly.months!, contains(12));
      expect(yearly.daysOfMonth, [15]);
    });

    // -- BYSETPOS roundtrips --

    test('Monthly BYSETPOS - last weekday of month roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(MonthlyRecurrence.byWeekday(
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.tuesday),
          RecurrenceDay(DayOfWeek.wednesday),
          RecurrenceDay(DayOfWeek.thursday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [-1],
        end: CountEnd(6),
      ));

      expect(result, isNotNull);
      expect(result, isA<MonthlyByWeekday>());
      final monthly = result as MonthlyByWeekday;
      expect(monthly.daysOfWeek.length, 5);
      expect(monthly.setPositions, [-1]);
      expect((monthly.end as CountEnd).count, 6);
    });

    test('Yearly BYSETPOS - last weekday of January roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(YearlyRecurrence.byWeekday(
        months: [1],
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.tuesday),
          RecurrenceDay(DayOfWeek.wednesday),
          RecurrenceDay(DayOfWeek.thursday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [-1],
        end: CountEnd(5),
      ));

      expect(result, isNotNull);
      expect(result, isA<YearlyByWeekday>());
      final yearly = result as YearlyByWeekday;
      expect(yearly.months, [1]);
      expect(yearly.daysOfWeek.length, 5);
      expect(yearly.setPositions, [-1]);
    });

    // -- Interval roundtrip --

    test('Weekly with interval=2 roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(const WeeklyRecurrence(
        interval: 2,
        daysOfWeek: [DayOfWeek.tuesday],
        end: CountEnd(8),
      ));

      expect(result, isNotNull);
      expect(result, isA<WeeklyRecurrence>());
      expect(result!.interval, 2);
    });

    // -- COUNT roundtrip --

    test('COUNT roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(const DailyRecurrence(end: CountEnd(30)));

      expect(result, isNotNull);
      expect(result!.end, isA<CountEnd>());
      expect((result.end as CountEnd).count, 30);
    });

    // -- UNTIL edge case roundtrips --

    test('UNTIL date-only roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final untilDate = DateTime.utc(2027, 6, 15);
      final result = await roundtrip(DailyRecurrence(end: UntilEnd(untilDate)));

      expect(result, isNotNull);
      expect(result!.end, isA<UntilEnd>());
      final until = (result.end as UntilEnd).until;
      // At minimum, the date should be preserved
      expect(until.year, 2027);
      expect(until.month, 6);
      expect(until.day, 15);
    });

    test('UNTIL date-time roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final untilDate = DateTime.utc(2027, 6, 15, 14, 30);
      final result = await roundtrip(DailyRecurrence(end: UntilEnd(untilDate)));

      expect(result, isNotNull);
      expect(result!.end, isA<UntilEnd>());
      final until = (result.end as UntilEnd).until;
      // Check date preserved. Time may or may not be preserved (iOS may truncate).
      expect(until.year, 2027);
      expect(until.month, 6);
      expect(until.day, 15);
      // Log time for diagnostic purposes (may be truncated on iOS)
      // ignore: avoid_print
      print('UNTIL date-time roundtrip: wrote ${untilDate.toIso8601String()}, '
          'got ${until.toIso8601String()}');
    });

    // -- No end condition (recurs forever) --

    test('Infinite recurrence roundtrip', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(const DailyRecurrence());

      expect(result, isNotNull);
      expect(result, isA<DailyRecurrence>());
      expect(result!.end, isNull);
    });

    // -- rruleString preservation --

    test('rruleString preserves platform RRULE', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final result = await roundtrip(const WeeklyRecurrence(
        daysOfWeek: [DayOfWeek.monday],
        end: CountEnd(5),
      ));

      expect(result, isNotNull);
      // The rruleString should be a valid RRULE string containing the key parts
      final rrule = result!.rruleString;
      expect(rrule, contains('FREQ=WEEKLY'));
      expect(rrule, contains('MO'));
      expect(rrule, contains('COUNT=5'));
    });
  });

  group('Recurrence Update Tests', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      calendarId = await plugin.createCalendar(
        name: 'Recurrence Update Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#00FF00',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    test('allEvents changes the recurrence rule for the whole series',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);

      final result = await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        recurrenceRule: Patch.set(const WeeklyRecurrence(
          daysOfWeek: [DayOfWeek.monday],
          end: CountEnd(5),
        )),
      );

      expect(result, series.eventId,
          reason: 'allEvents returns the same event ID');
      final updated = await plugin.getEvent(series.eventId);
      expect(updated, isNotNull);
      expect(updated!.isRecurring, isTrue);
      final weekly = updated.recurrenceRule as WeeklyRecurrence;
      expect(weekly.daysOfWeek, [DayOfWeek.monday],
          reason: 'daysOfWeek must round-trip through update');
      expect((weekly.end as CountEnd).count, 5,
          reason: 'count must round-trip through update');
    });

    test('allEvents with Patch.clear removes recurrence', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);

      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        recurrenceRule: const Patch.clear(),
      );

      final updated = await plugin.getEvent(series.eventId);
      expect(updated, isNotNull);
      expect(updated!.isRecurring, isFalse);
      expect(updated.recurrenceRule, isNull);
    });

    // Known failure on Android emulator: the emulator's Calendar Provider
    // doesn't propagate the title change to the anchor occurrence after a
    // thisAndFollowing split. Passes on real Android devices.
    test('thisAndFollowing splits so the anchor occurrence carries the change',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6),
          reason: 'the daily series should have expanded into occurrences');
      final splitPoint = occurrences[4];
      final splitMillis = splitPoint.startDate.millisecondsSinceEpoch;

      final newSeriesId = await plugin.updateRecurring(
        splitPoint.instanceId,
        EventSpan.thisAndFollowing,
        title: 'Split Tail',
      );

      // The original master series is now truncated — only occurrences
      // before the split point should remain under its eventId, and none
      // of them are touched.
      final remainingMaster = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(remainingMaster, isNotEmpty,
          reason: 'occurrences before the split must survive');
      expect(
        remainingMaster
            .every((e) => e.startDate.millisecondsSinceEpoch < splitMillis),
        isTrue,
        reason: 'the original series must not extend past the split point',
      );
      expect(remainingMaster.every((e) => e.title == 'Daily Series'), isTrue,
          reason: 'occurrences before the split must keep the original title');

      // The new series starts at the split point and carries the new title.
      final newSeriesOccurrences =
          await occurrencesOf(plugin, calendarId!, newSeriesId, series.start);
      final atSplit = newSeriesOccurrences
          .where((e) => e.startDate.millisecondsSinceEpoch == splitMillis)
          .toList();
      expect(atSplit, isNotEmpty,
          reason:
              'the new series should have an occurrence at the split point');
      expect(atSplit.first.title, 'Split Tail',
          reason: 'the anchor occurrence must receive the change');
    });

    test('thisAndFollowing can change the rule from the split point onward',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final splitPoint = occurrences[4];
      final splitMillis = splitPoint.startDate.millisecondsSinceEpoch;

      final newSeriesId = await plugin.updateRecurring(
        splitPoint.instanceId,
        EventSpan.thisAndFollowing,
        recurrenceRule: Patch.set(const WeeklyRecurrence(end: CountEnd(3))),
      );

      // The new series carries the new rule type with an end count.
      // Asserting the exact CountEnd value isn't portable: Android honors
      // the literal `CountEnd(3)`, while iOS's `.futureEvents` save
      // normalizes the count (returns 2 for `COUNT=3` requested — EventKit
      // appears to fit the new rule into the original master's lifespan).
      // Cross-platform contract is "WEEKLY with some CountEnd"; an exact
      // value would require either platform-specific assertions or a fix
      // on the iOS side to honor the rule literally.
      // TODO(updateRecurring.thisAndFollowing/iOS): investigate why
      // `.futureEvents` save normalizes the new rule's COUNT.
      final newSeries = await plugin.getEvent(newSeriesId);
      expect(newSeries, isNotNull);
      final weekly = newSeries!.recurrenceRule as WeeklyRecurrence;
      expect(weekly.end, isA<CountEnd>(),
          reason: 'the new rule must end via a count, not infinite');

      // The new series starts at the split point — i.e. the anchor
      // occurrence is now the first occurrence of the new series.
      expect(newSeries.startDate.millisecondsSinceEpoch, splitMillis,
          reason: 'the new series must start at the split point');
    });

    test(
        'thisAndFollowing with a rule on a new weekday moves the split '
        'occurrence to that weekday instead of leaving it behind (#140)',
        () async {
      // Issue #140: a Saturday series split at one Saturday with a "from now
      // on, Sundays" rule kept that Saturday as an extra first occurrence of
      // the new series. The split occurrence must move to the first day the
      // new rule generates, not survive alongside it.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createWeeklySeriesOnOwnWeekday(plugin, calendarId!);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 50);
      expect(before.length, greaterThanOrEqualTo(4),
          reason: 'the weekly series should have expanded into occurrences');
      final split = before[2];

      // Weekly on the new weekday until 20 days past the split: exactly
      // three occurrences (split + 1, + 8, + 15 days). UNTIL rather than
      // COUNT because iOS's `.futureEvents` save normalises a COUNT on a
      // split (see the TODO in the rule-change test above).
      final newSeriesId = await plugin.updateRecurring(
        split.instanceId,
        EventSpan.thisAndFollowing,
        recurrenceRule: Patch.set(WeeklyRecurrence(
          daysOfWeek: [series.newDay],
          end: UntilEnd(split.startDate.add(const Duration(days: 20))),
        )),
      );

      // The two occurrences before the split stay on the old weekday under
      // the original id, and nothing later survives there.
      expectTruncatedMaster(
        await occurrencesOf(plugin, calendarId!, series.eventId, series.start,
            windowDays: 50),
        before: split.startDate,
      );

      // The new series lives entirely on the new weekday, starting the day
      // after the split occurrence — i.e. the split occurrence itself moved.
      expectReanchoredWeekly(
        await occurrencesOf(plugin, calendarId!, newSeriesId, series.start,
            windowDays: 50),
        on: series.newDay,
        firstAt: split.startDate.add(const Duration(days: 1)),
        orphanAt: split.startDate,
      );
    });

    test(
        'allEvents with a rule on a new weekday moves the series anchor to '
        'that weekday instead of leaving it behind (#140)', () async {
      // The allEvents half of #140: a rule-only patch must re-anchor the
      // series start on the first day the new rule generates. Without that
      // the start is never rewritten and the provider keeps the old weekday
      // as an extra first occurrence.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createWeeklySeriesOnOwnWeekday(plugin, calendarId!);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 50);
      expect(before, isNotEmpty,
          reason: 'the weekly series should have expanded into occurrences');
      final oldStart = before.first.startDate;

      // Weekly on the new weekday until 20 days past the start: exactly three
      // occurrences (start + 1, + 8, + 15 days).
      final result = await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        recurrenceRule: Patch.set(WeeklyRecurrence(
          daysOfWeek: [series.newDay],
          end: UntilEnd(oldStart.add(const Duration(days: 20))),
        )),
      );
      expect(result, series.eventId,
          reason: 'allEvents returns the same event ID');

      final updated = await plugin.getEvent(series.eventId);
      expect(updated, isNotNull);
      expect(
        updated!.startDate.millisecondsSinceEpoch,
        oldStart.add(const Duration(days: 1)).millisecondsSinceEpoch,
        reason: 'the series anchor must move to the first day the new rule '
            'generates',
      );

      expectReanchoredWeekly(
        await occurrencesOf(plugin, calendarId!, series.eventId, series.start,
            windowDays: 50),
        on: series.newDay,
        firstAt: oldStart.add(const Duration(days: 1)),
        orphanAt: oldStart,
      );
    });

    test(
        'thisAndFollowing with a rule on a new weekday re-anchors an all-day '
        'series on that weekday', () async {
      // All-day days are framed differently per platform (Android walks
      // them in UTC, iOS in the device zone), so the re-anchor must land on
      // the next calendar day, not a day early or late around midnight.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      final today = DateTime.now();
      final start =
          DateTime(today.year, today.month, today.day + 1); // local midnight
      final newDay = weekdayOf(start.add(const Duration(days: 1)));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'All-Day Weekly Series',
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
        isAllDay: true,
        recurrenceRule: WeeklyRecurrence(
          daysOfWeek: [weekdayOf(start)],
          end: const CountEnd(6),
        ),
      );

      final before = await occurrencesOf(plugin, calendarId!, eventId, start,
          windowDays: 50);
      expect(before.length, greaterThanOrEqualTo(4),
          reason: 'the weekly series should have expanded into occurrences');
      final split = before[2];
      expect(split.isAllDay, isTrue);
      final splitDate = DateTime(
          split.startDate.year, split.startDate.month, split.startDate.day);

      // A date-only UNTIL (UTC midnight serialises without a time), 20 days
      // past the split: exactly three occurrences (split + 1, + 8, + 15).
      final until =
          DateTime.utc(splitDate.year, splitDate.month, splitDate.day + 20);
      final newSeriesId = await plugin.updateRecurring(
        split.instanceId,
        EventSpan.thisAndFollowing,
        recurrenceRule: Patch.set(WeeklyRecurrence(
          daysOfWeek: [newDay],
          end: UntilEnd(until),
        )),
      );

      // The split occurrence moves to the calendar day after it, and neither
      // series keeps anything on the split day.
      expectReanchoredWeekly(
        await occurrencesOf(plugin, calendarId!, newSeriesId, start,
            windowDays: 50),
        on: newDay,
        firstAt: DateTime(splitDate.year, splitDate.month, splitDate.day + 1),
        orphanAt: split.startDate,
        allDay: true,
      );
      expectTruncatedMaster(
        await occurrencesOf(plugin, calendarId!, eventId, start,
            windowDays: 50),
        before: split.startDate,
      );
    });

    // The re-anchor walk gives up after five years. Rather than anchor the
    // series on a day the rule never generates — the orphan #140 removes —
    // the update is refused before anything is written, for both spans: the
    // master keeps every occurrence, and a split creates no new series.
    for (final span in EventSpan.values) {
      test(
          'a rule that generates no occurrence is refused with invalidArguments '
          'for $span and leaves the series untouched', () async {
        expect(calendarId, isNotNull,
            reason: 'setUpAll must create a calendar');
        final series = await createWeeklySeries(plugin, calendarId!, count: 4);
        final before = await occurrencesOf(
            plugin, calendarId!, series.eventId, series.start,
            windowDays: 45);
        expect(before.length, greaterThanOrEqualTo(3),
            reason: 'the weekly series should have expanded into occurrences');
        final windowEnd = series.start.add(const Duration(days: 45));
        final calendarBefore = await plugin.listEvents(
            series.start.subtract(const Duration(days: 1)), windowEnd,
            calendarIds: [calendarId!]);
        final id =
            span == EventSpan.allEvents ? series.eventId : before[2].instanceId;

        await expectLater(
          plugin.updateRecurring(
            id,
            span,
            // 30 February: constructible, never generated.
            recurrenceRule:
                Patch.set(YearlyRecurrence(months: [2], daysOfMonth: [30])),
          ),
          throwsA(isA<DeviceCalendarException>().having((e) => e.errorCode,
              'errorCode', DeviceCalendarError.invalidArguments)),
          reason: '$span must refuse a rule that never generates',
        );

        final after = await occurrencesOf(
            plugin, calendarId!, series.eventId, series.start,
            windowDays: 45);
        expect(
          after.map((e) => e.startDate).toList(),
          before.map((e) => e.startDate).toList(),
          reason: 'a refused $span rule must leave the series as it was',
        );
        final calendarAfter = await plugin.listEvents(
            series.start.subtract(const Duration(days: 1)), windowEnd,
            calendarIds: [calendarId!]);
        expect(calendarAfter.length, calendarBefore.length,
            reason: 'a refused $span rule must not create a new series');
      });
    }

    test(
        'thisAndFollowing with Patch.clear turns the anchor into a standalone '
        'non-recurring event and drops future occurrences (#93)', () async {
      // Issue #93's "this and future" case: split the series at the chosen
      // occurrence, make that occurrence a standalone non-recurring event,
      // and remove every later occurrence. Past occurrences stay in the
      // original series.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final splitPoint = occurrences[4];
      final splitMillis = splitPoint.startDate.millisecondsSinceEpoch;

      final standaloneId = await plugin.updateRecurring(
        splitPoint.instanceId,
        EventSpan.thisAndFollowing,
        recurrenceRule: const Patch.clear(),
      );

      // The original master keeps only the occurrences before the split.
      final remainingMaster = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(remainingMaster, isNotEmpty,
          reason: 'occurrences before the split must survive');
      expect(
        remainingMaster
            .every((e) => e.startDate.millisecondsSinceEpoch < splitMillis),
        isTrue,
        reason: 'the original series must not extend past the split point',
      );

      // The anchor is now a standalone non-recurring event at the split point.
      final standalone = await plugin.getEvent(standaloneId);
      expect(standalone, isNotNull);
      expect(standalone!.recurrenceRule, isNull,
          reason: 'the detached event must carry no recurrence rule');
      expect(standalone.startDate.millisecondsSinceEpoch, splitMillis,
          reason: 'the standalone event must sit at the split point');

      // No future occurrences: the detached event expands to exactly one,
      // and nothing past the split survives under the new id.
      final detachedOccurrences =
          await occurrencesOf(plugin, calendarId!, standaloneId, series.start);
      expect(detachedOccurrences.length, 1,
          reason: 'a non-recurring event expands to a single occurrence');
      expect(detachedOccurrences.single.startDate.millisecondsSinceEpoch,
          splitMillis);
    });

    test('updateEvent with an instance ID edits only the one occurrence',
        skip: _isAndroidEmulator
            ? 'Android emulator Calendar Provider drops master occurrences '
                'after a CONTENT_EXCEPTION_URI insert; runs on physical devices'
            : false, () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final target = occurrences[4];
      final targetMillis = target.startDate.millisecondsSinceEpoch;

      await plugin.updateEvent(
        eventId: target.instanceId,
        title: 'Just this one',
      );

      // updateEvent returns no ID for the detached exception (the platforms
      // disagree on what it would be), so the edit is verified through
      // listEvents: the detached exception must surface in the window with
      // the new title at the targeted moment.
      final listed = await plugin.listEvents(
        series.start.subtract(const Duration(days: 1)),
        series.start.add(const Duration(days: 14)),
        calendarIds: [calendarId!],
      );
      expect(
        listed.any((e) =>
            e.title == 'Just this one' &&
            e.startDate.millisecondsSinceEpoch == targetMillis),
        isTrue,
        reason: 'listEvents must include the detached exception',
      );

      // The master series should still expand into occurrences — all
      // except the targeted one should keep the original title.
      final initialCount = occurrences.length;
      final afterUpdate = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(afterUpdate.length, initialCount - 1,
          reason:
              'master should have initialCount-1 occurrences (targeted one is now an exception)');
      expect(
        afterUpdate.every((e) => e.title == 'Daily Series'),
        isTrue,
        reason: 'untouched occurrences must keep the original title',
      );

      // The master row itself must not be corrupted.
      final master = await plugin.getEvent(series.eventId);
      expect(master, isNotNull);
      expect(master!.title, 'Daily Series',
          reason: 'the master event row must keep its original title');
    });

    test(
        'updateEvent with an instance ID rejects a startDate past the '
        'occurrence end', () async {
      // With no endDate, the occurrence's own end stays put — so a startDate
      // beyond it would invert the range. Both platforms must refuse with
      // invalidArguments rather than save an inverted event.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final target = occurrences[4];

      await expectLater(
        plugin.updateEvent(
          eventId: target.instanceId,
          startDate: target.startDate.add(const Duration(days: 2)),
        ),
        throwsA(isA<DeviceCalendarException>().having(
          (e) => e.errorCode,
          'errorCode',
          DeviceCalendarError.invalidArguments,
        )),
      );
    });

    test('updateEvent on a recurring eventId updates the whole series',
        () async {
      // Per the v0.3.0 contract, `updateEvent` on a recurring event always
      // affects the entire series — semantically equivalent to
      // `updateRecurring(EventSpan.allEvents)`. Guards against the two
      // methods drifting apart on the native side.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);

      await plugin.updateEvent(
        eventId: series.eventId,
        title: 'Legacy Updated',
      );

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences, isNotEmpty);
      expect(occurrences.every((e) => e.title == 'Legacy Updated'), isTrue,
          reason: 'every occurrence of the series must reflect the update');
    });
  });

  // Anchor-shift: `start` moves the anchored occurrence to a new instant and
  // translates the whole scope by the wall-clock delta — time and day
  // together (issue #103). Most cases create the series in UTC, so wall-clock
  // deltas equal absolute deltas and the assertions are timezone-independent;
  // the final case deliberately pins a DST-observing *event* timezone to cover
  // the wall-clock path the UTC cases can't.
  group('Recurrence Anchor-Shift Tests (#103)', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();
      calendarId = await plugin.createCalendar(
        name: 'Anchor Shift Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#00FFFF',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    /// Asserts each occurrence in [after] sits [delta] after the matching one
    /// in [before] (compared as instants).
    void expectShifted(List<Event> before, List<Event> after, Duration delta) {
      expect(after.length, before.length,
          reason: 'the occurrence count must be preserved by a pure shift');
      for (var i = 0; i < before.length; i++) {
        expect(
          after[i].startDate.millisecondsSinceEpoch,
          before[i].startDate.millisecondsSinceEpoch + delta.inMilliseconds,
          reason: 'occurrence $i must move by exactly $delta',
        );
      }
    }

    test('allEvents start shift moves every occurrence by the time delta',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 6);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before.length, greaterThanOrEqualTo(3));

      // Move the whole series two hours later.
      final newStart = before.first.startDate.add(const Duration(hours: 2));
      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newStart,
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expectShifted(before, after, const Duration(hours: 2));
    });

    test('allEvents start shift moves a weekly series to a new weekday',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createWeeklySeries(plugin, calendarId!, count: 4);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before.length, greaterThanOrEqualTo(2),
          reason: 'the weekly series should expand into occurrences');

      // Move the series one day later — Monday-style series becomes Tuesday.
      final newStart = before.first.startDate.add(const Duration(days: 1));
      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newStart,
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expectShifted(before, after, const Duration(days: 1));
      expect(
        after.first.startDate.weekday,
        before.first.startDate.add(const Duration(days: 1)).weekday,
        reason: 'the recurring weekday must advance by one',
      );
    });

    test(
        'allEvents start shift changes day and time together (crosses midnight)',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 6);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before.length, greaterThanOrEqualTo(3));

      // +1 day +3 hours: a combined move that necessarily crosses midnight.
      const delta = Duration(days: 1, hours: 3);
      final newStart = before.first.startDate.add(delta);
      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newStart,
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 16);
      expectShifted(before, after, delta);
    });

    test('thisAndFollowing start shift moves only the anchor and later ones',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before.length, greaterThanOrEqualTo(6));
      final splitIndex = 4;
      final splitMillis = before[splitIndex].startDate.millisecondsSinceEpoch;

      final newSeriesId = await plugin.updateRecurring(
        before[splitIndex].instanceId,
        EventSpan.thisAndFollowing,
        start: before[splitIndex].startDate.add(const Duration(hours: 2)),
      );

      // Occurrences before the split stay put under the original series.
      final remainingMaster = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(remainingMaster, isNotEmpty);
      expect(
        remainingMaster
            .every((e) => e.startDate.millisecondsSinceEpoch < splitMillis),
        isTrue,
        reason: 'occurrences before the split must be untouched',
      );

      // The new series carries the anchor and later ones, each two hours later.
      final newOccurrences = await occurrencesOf(
          plugin, calendarId!, newSeriesId, series.start,
          windowDays: 16);
      expect(newOccurrences, isNotEmpty);
      expect(
        newOccurrences.first.startDate.millisecondsSinceEpoch,
        splitMillis + const Duration(hours: 2).inMilliseconds,
        reason: 'the anchor occurrence must move two hours later',
      );
    });

    test('day shift on an explicit-BYDAY rule without a rule throws', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Pin the rule to the start's own weekday so the +1-day shift lands on a
      // weekday the rule does not list — an ambiguous move we refuse.
      final startDay = DateTime.now().add(const Duration(hours: 1));
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [weekdayOf(startDay)], start: startDay);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before, isNotEmpty);

      await expectLater(
        plugin.updateRecurring(
          before.first.instanceId,
          EventSpan.allEvents,
          start: before.first.startDate.add(const Duration(days: 1)),
        ),
        throwsA(isA<DeviceCalendarException>().having((e) => e.errorCode,
            'errorCode', DeviceCalendarError.invalidArguments)),
      );
    });

    test('time-only shift on an explicit-BYDAY rule is allowed', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final startDay = DateTime.now().add(const Duration(hours: 1));
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [weekdayOf(startDay)], start: startDay);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before, isNotEmpty);

      // +2h same calendar day — weekday unchanged, so no rule conflict.
      final newStart = before.first.startDate.add(const Duration(hours: 2));
      // Guard against the +2h crossing midnight in this run. Production checks
      // the day move in the event's UTC timezone, so guard in UTC too — a
      // local-frame guard flakes when only the UTC date rolls over.
      if (newStart.toUtc().weekday == before.first.startDate.toUtc().weekday) {
        await plugin.updateRecurring(
          before.first.instanceId,
          EventSpan.allEvents,
          start: newStart,
        );
        final after = await occurrencesOf(
            plugin, calendarId!, series.eventId, series.start,
            windowDays: 45);
        expectShifted(before, after, const Duration(hours: 2));
      }
    });

    test('day shift on an explicit-BYDAY rule WITH a matching rule succeeds',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final startDay = DateTime.now().add(const Duration(hours: 1));
      final oldDay = weekdayOf(startDay);
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [oldDay], start: startDay);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before, isNotEmpty);

      // The series is stored in UTC and the rule's BYDAY is expanded in that
      // frame (production checks the day move in the event's timezone too), so
      // derive the new weekday and assert in UTC. Reading weekdays in device-
      // local time flakes whenever local and UTC fall on different calendar
      // days — e.g. the early-morning hours in Australia/Sydney (#103).
      final newStart = before.first.startDate.add(const Duration(days: 1));
      final newDay = weekdayOf(newStart.toUtc());

      // Passing the new rule alongside start resolves the ambiguity.
      final result = await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newStart,
        recurrenceRule: Patch.set(WeeklyRecurrence(
          daysOfWeek: [newDay],
          end: const CountEnd(4),
        )),
      );
      expect(result, isNotEmpty);
      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(after, isNotEmpty);
      expect(
          after.every(
              (e) => e.startDate.toUtc().weekday == newStart.toUtc().weekday),
          isTrue,
          reason: 'every occurrence should now fall on the new weekday');
    });

    test(
        'day shift WITH a rule that does not fit the shifted day walks on to '
        'the first day the rule generates', () async {
      // The documented composition: `start` picks the anchor first, then the
      // new rule walks forward from it when that day isn't one it generates.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final startDay = DateTime.now().toUtc().add(const Duration(hours: 1));
      final oldDay = weekdayOf(startDay);
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [oldDay], start: startDay);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before, isNotEmpty);

      // Shift one day on; pin the rule to the day after that (in UTC, the
      // series' frame — see the test above).
      final newStart = before.first.startDate.add(const Duration(days: 1));
      final ruleDay = weekdayOf(newStart.toUtc().add(const Duration(days: 1)));
      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newStart,
        recurrenceRule: Patch.set(WeeklyRecurrence(
          daysOfWeek: [ruleDay],
          end: const CountEnd(3),
        )),
      );

      // The anchor moves from the passed start on to the first day the rule
      // generates; the passed start itself is not an occurrence.
      expectReanchoredWeekly(
        await occurrencesOf(plugin, calendarId!, series.eventId, series.start,
            windowDays: 45),
        on: ruleDay,
        firstAt: newStart.add(const Duration(days: 1)),
        orphanAt: newStart,
      );
    });

    test(
        'allEvents shift keeps wall-clock across DST in a non-UTC event '
        'timezone', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');

      // Every other case here runs in UTC (no DST). This one pins a
      // DST-observing *event* timezone — distinct from the device timezone the
      // harness varies — to exercise the path where the shift counts calendar
      // days and re-applies the wall-clock time in the event's zone, and where
      // listEvents must expand a series whose UTC offset changes mid-stream.
      //
      // US Pacific falls back on 2026-11-01 (PDT UTC-7 -> PST UTC-8). At 09:00
      // local that is 16:00 UTC before the switch and 17:00 UTC after it.
      const pacific = 'America/Los_Angeles';
      final fallBack = DateTime.utc(2026, 11, 1);
      int expectedUtcHour(Event occ) =>
          occ.startDate.toUtc().isBefore(fallBack) ? 16 : 17;

      // Anchor at 2026-10-30 09:00 PDT = 16:00 UTC, daily, straddling the
      // fall-back so the series carries 09:00 Pacific on both offsets.
      final anchor = DateTime.utc(2026, 10, 30, 16, 0);
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Pacific DST Series',
        startDate: anchor,
        endDate: anchor.add(const Duration(hours: 1)),
        recurrenceRule: DailyRecurrence(end: const CountEnd(6)),
        timeZone: pacific,
      );

      final before = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 10);
      expect(before.length, greaterThanOrEqualTo(4),
          reason: 'the daily series must expand across the transition');
      for (final occ in before) {
        expect(occ.startDate.toUtc().hour, expectedUtcHour(occ),
            reason: 'the created series must stay at 09:00 Pacific across DST');
      }

      // Shift the anchor one calendar day later (2026-10-31 09:00 PDT = 16:00
      // UTC). The shifted series still crosses the fall-back, so a DST-safe
      // shift keeps every occurrence at 09:00 Pacific.
      final newAnchor = DateTime.utc(2026, 10, 31, 16, 0);
      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newAnchor,
      );

      final after = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 10);
      expect(after, isNotEmpty);
      expect(after.first.startDate.toUtc().millisecondsSinceEpoch,
          newAnchor.millisecondsSinceEpoch,
          reason: 'the new anchor must land exactly at 09:00 PDT');
      for (final occ in after) {
        expect(occ.startDate.toUtc().hour, expectedUtcHour(occ),
            reason: 'after the shift the series must stay at 09:00 Pacific '
                '(DST-safe day count, not a flat 24h add)');
      }
    });
  });

  group('Recurrence Delete Tests', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      calendarId = await plugin.createCalendar(
        name: 'Recurrence Delete Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#0000FF',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    test('allEvents deletes the whole series', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);

      // The series should have expanded into occurrences first.
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before, isNotEmpty);

      await plugin.deleteRecurring(series.eventId, EventSpan.allEvents);

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(after, isEmpty, reason: 'the whole series should be gone');
      expect(await plugin.getEvent(series.eventId), isNull);
    });

    test('thisAndFollowing removes the anchor and every later occurrence',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final anchor = occurrences[4];
      final anchorMillis = anchor.startDate.millisecondsSinceEpoch;

      await plugin.deleteRecurring(
        anchor.instanceId,
        EventSpan.thisAndFollowing,
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);

      // The anchor and everything after it are gone.
      expect(
        after.every((e) => e.startDate.millisecondsSinceEpoch < anchorMillis),
        isTrue,
        reason: 'the anchor and later occurrences must be removed',
      );
      // Occurrences before the anchor survive.
      expect(after, isNotEmpty,
          reason: 'occurrences before the anchor must survive');
    });

    test('deleteEvent with an instance ID removes only the one occurrence',
        skip: _isAndroidEmulator
            ? 'Android emulator Calendar Provider drops master occurrences '
                'after a CONTENT_EXCEPTION_URI insert; runs on physical devices'
            : false, () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final initialCount = occurrences.length;
      final target = occurrences[4];
      final targetMillis = target.startDate.millisecondsSinceEpoch;

      await plugin.deleteEvent(eventId: target.instanceId);

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);

      // The targeted occurrence is gone.
      expect(
        after.any((e) => e.startDate.millisecondsSinceEpoch == targetMillis),
        isFalse,
        reason: 'the targeted occurrence must be removed',
      );
      // Exactly one occurrence was removed; the rest survive.
      expect(after.length, initialCount - 1,
          reason: 'only the one occurrence should be removed');
    });

    test('deleteEvent on a recurring eventId removes the whole series',
        () async {
      // Per the v0.3.0 contract, `deleteEvent` on a recurring event always
      // removes the entire series — semantically equivalent to
      // `deleteRecurring(EventSpan.allEvents)`. Guards against the two
      // methods drifting apart on the native side.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);

      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before, isNotEmpty);

      await plugin.deleteEvent(eventId: series.eventId);

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(after, isEmpty, reason: 'the whole series should be gone');
      expect(await plugin.getEvent(series.eventId), isNull);
    });
  });

  group('Recurrence Read Tests (#122)', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      calendarId = await plugin.createCalendar(
        name: 'Recurrence Read Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#3366FF',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    // Android stores an all-day occurrence at UTC midnight and reports it at
    // local midnight; its instance ID carries the stored instant, and
    // getEvent must resolve that ID exactly as listEvents handed it out.
    test('getEvent resolves an all-day recurring occurrence by instance ID',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series =
          await createAllDayDailySeries(plugin, calendarId!, count: 4);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
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

    test('getEvent resolves a timed recurring occurrence by instance ID',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 4);

      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
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

    // Android stores a recurring master as DTSTART + DURATION with no DTEND,
    // so the master's end must come from its duration.
    test('getEvent returns a timed master with its real end date', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 3);

      final master = await plugin.getEvent(series.eventId);
      expect(master, isNotNull);
      expect(master!.isRecurring, isTrue);
      expect(
          master.endDate.difference(master.startDate), const Duration(hours: 1),
          reason: 'the master must carry the series duration, not a '
              'zero-length end');
    });

    test('getEvent returns an all-day master ending at the next local midnight',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series =
          await createAllDayDailySeries(plugin, calendarId!, count: 3);

      final master = await plugin.getEvent(series.eventId);
      expect(master, isNotNull);
      expect(master!.isAllDay, isTrue);
      expect(master.startDate, series.start);
      expect(master.endDate, series.end,
          reason: 'an all-day master spans its day, ending at the next '
              'local midnight');
    });
  });
}
