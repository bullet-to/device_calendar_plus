import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart'
    show DeviceCalendarPlusPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';
import 'test_helpers.dart';
import 'test_seed.dart';

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

/// The all-day twin of [createWeeklySeriesOnOwnWeekday], for the #144 tests:
/// a weekly series titled [title], pinned (BYDAY) to its own weekday, with
/// [count] occurrences, seeded with its occurrences listed. It starts in two
/// days, so a day-earlier move is still in the future. All-day, so the
/// weekday is read in local time, the frame the start is given in. Checks
/// the group's calendar exists first.
Future<SeededSeries> createAllDayWeeklySeriesOnOwnWeekday(
  DeviceCalendar plugin,
  String? calendarId, {
  required String title,
  int count = 4,
}) {
  final start = localMidnight(2);
  return seedSeries(
    plugin,
    calendarId,
    count: count,
    minOccurrences: 1,
    windowDays: 30,
    create: (plugin, calendarId, {int count = 4}) => createWeeklySeries(
        plugin, calendarId,
        title: title,
        count: count,
        daysOfWeek: [weekdayOf(start)],
        start: start,
        isAllDay: true),
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

/// Creates a one-off (non-recurring) event titled [title], an hour from now
/// at a whole second, and returns its ID with an instance ID carrying its own
/// start as the occurrence timestamp — a timestamp that falls inside the
/// event, for the #124 tests that hand a one-off to a series-split call.
Future<({String eventId, String instanceId})> createOneOffWithTimestamp(
  DeviceCalendar plugin,
  String calendarId,
  String title,
) async {
  final start = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600) * 1000,
  );
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: title,
    startDate: start,
    endDate: start.add(const Duration(hours: 1)),
  );
  return (
    eventId: eventId,
    instanceId: '$eventId@${start.millisecondsSinceEpoch}',
  );
}

/// Moves [series]' occurrence at [index] by [shift] as a per-occurrence edit,
/// retitling it [title] so it can be found afterwards (see [eventsTitled]),
/// and returns the detached copy as listed at its new time, asserting it
/// appears there exactly once.
Future<Event> moveOccurrence(
  DeviceCalendar plugin,
  String calendarId,
  SeededSeries series,
  int index,
  Duration shift,
  String title,
) async {
  final occurrence = series.occurrences[index];
  final movedStart = occurrence.startDate.add(shift);
  await plugin.updateEvent(
    instanceId: occurrence.instanceId,
    title: title,
    startDate: movedStart,
    endDate: occurrence.endDate.add(shift),
  );
  final moved = await detachedAt(plugin, calendarId, title, series, movedStart);
  expect(
    moved,
    hasLength(1),
    reason: 'the moved occurrence must appear once, at its new time',
  );
  return moved.single;
}

/// The events titled [title] listed at exactly [instant]: a detached
/// occurrence found at the time it was moved to.
Future<List<Event>> detachedAt(
  DeviceCalendar plugin,
  String calendarId,
  String title,
  SeededSeries series,
  DateTime instant,
) async {
  final listed = await eventsTitled(plugin, calendarId, title, series.start);
  return listed
      .where(
        (e) =>
            e.startDate.millisecondsSinceEpoch ==
            instant.millisecondsSinceEpoch,
      )
      .toList();
}

/// The next first Sunday of November, the day US clocks fall back, at UTC
/// midnight.
DateTime nextUsFallBack() {
  final now = DateTime.now().toUtc();
  for (var year = now.year;; year++) {
    final nov1 = DateTime.utc(year, 11, 1);
    final sunday =
        nov1.add(Duration(days: (DateTime.sunday - nov1.weekday) % 7));
    if (sunday.isAfter(now)) return sunday;
  }
}

/// Asserts a detached occurrence ([moved], as [moveOccurrence] returned it)
/// went with a `thisAndFollowing` split: absent from the listing and, on
/// Android, its own Events row gone too. There a detached occurrence is its
/// own row, and listEvents reads the Instances cache, which the truncate
/// rebuilds from the master alone — so an orphaned row and a removed one
/// look the same in a listing until the cache next regenerates. The bare-ID
/// read goes straight to the row. (iOS reports the master's identifier for
/// a detached occurrence, so the same read there would find the master.)
Future<void> expectDetachedGone(
  DeviceCalendar plugin,
  String calendarId,
  String title,
  SeededSeries series,
  Event moved,
) async {
  expect(
    await detachedAt(plugin, calendarId, title, series, moved.startDate),
    isEmpty,
    reason:
        'a detached occurrence whose slot is past the split must go '
        'with the rest of "this and following"',
  );
  if (Platform.isAndroid) {
    expect(
      await plugin.getEvent(moved.eventId),
      isNull,
      reason:
          'the detached occurrence\'s own row must be removed, not '
          'just dropped from the Instances cache',
    );
  }
}

/// Asserts a detached occurrence survived a `thisAndFollowing` split: still
/// listed, and on Android its own Events row intact (see [expectDetachedGone]
/// for why the row read is Android-only). [listed] is false where the
/// listing half is gated off for the emulator (#159); the row read still runs.
Future<void> expectDetachedKept(
  DeviceCalendar plugin,
  String calendarId,
  String title,
  SeededSeries series,
  Event moved, {
  bool listed = true,
}) async {
  if (listed) {
    expect(
      await detachedAt(plugin, calendarId, title, series, moved.startDate),
      hasLength(1),
      reason:
          'a detached occurrence whose slot is before the split must '
          'survive it',
    );
  }
  if (Platform.isAndroid) {
    expect(
      await plugin.getEvent(moved.eventId),
      isNotNull,
      reason: 'the detached occurrence must keep its own row',
    );
  }
}

/// Asserts the three-occurrence series [eventId] reads back at whole seconds
/// (#165): its master from [wholeSecond] to an hour on, its first occurrence
/// at [wholeSecond], and every occurrence listed from [windowStart] on a
/// whole second.
Future<void> expectWholeSecondSeries(
  DeviceCalendar plugin,
  String calendarId,
  String eventId,
  DateTime windowStart,
  int wholeSecond,
) async {
  final master = await plugin.getEvent(eventId);
  final occurrences = await occurrencesOf(
      plugin, calendarId, eventId, windowStart,
      windowDays: 30);
  expect(occurrences, hasLength(3));
  expect(master, isNotNull, reason: 'the series master must read back');
  expect(master!.startDate.millisecondsSinceEpoch, wholeSecond,
      reason: 'the series start must be stored at whole seconds');
  expect(master.endDate.millisecondsSinceEpoch, wholeSecond + 3600000,
      reason: 'the series end must be stored at whole seconds');
  expect(occurrences.first.startDate.millisecondsSinceEpoch, wholeSecond,
      reason: 'the first occurrence must start where its master does');
  expect(startsOf(occurrences).every((ms) => ms % 1000 == 0), isTrue,
      reason: 'every occurrence must start at a whole second');
}

/// Matches a [PlatformException] carrying [code].
Matcher throwsPlatformCode(String code) =>
    throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

/// Creates a four-count weekly series, runs [act] against it — on the series
/// for [EventSpan.allEvents], on its third occurrence otherwise — and expects
/// it to throw [throws]. The refusal must leave the series' occurrences as
/// they were and create no new series in the calendar.
Future<void> expectRefusalLeavesSeriesUntouched(
  DeviceCalendar plugin,
  String calendarId,
  EventSpan span,
  Future<void> Function(String targetId) act,
  Matcher throws, {
  String? reason,
}) async {
  final series = await createWeeklySeries(plugin, calendarId, count: 4);
  final before = await occurrencesOf(
      plugin, calendarId, series.eventId, series.start,
      windowDays: 45);
  expect(before.length, greaterThanOrEqualTo(3),
      reason: 'the weekly series should have expanded into occurrences');
  final windowStart = series.start.subtract(const Duration(days: 1));
  final windowEnd = series.start.add(const Duration(days: 45));
  final calendarBefore = await plugin.listEvents(windowStart, windowEnd,
      calendarIds: [calendarId]);
  final targetId =
      span == EventSpan.allEvents ? series.eventId : before[2].instanceId;

  await expectLater(act(targetId), throws, reason: reason);

  final after = await occurrencesOf(
      plugin, calendarId, series.eventId, series.start,
      windowDays: 45);
  expect(
    after.map((e) => e.startDate).toList(),
    before.map((e) => e.startDate).toList(),
    reason: 'a refused $span rule must leave the series as it was',
  );
  final calendarAfter = await plugin.listEvents(windowStart, windowEnd,
      calendarIds: [calendarId]);
  expect(calendarAfter.length, calendarBefore.length,
      reason: 'a refused $span rule must not create a new series');
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

    // -- Unsupported rules (#125) --

    for (final rrule in ['FREQ=HOURLY;COUNT=3', 'NOT-A-RULE']) {
      test(
          'createEvent refuses a rule outside DAILY/WEEKLY/MONTHLY/YEARLY '
          '("$rrule") and writes nothing (#125)', () async {
        // The typed RecurrenceRule only ever emits the four supported
        // frequencies, so this drives the platform layer directly with the
        // raw string. iOS used to drop a rule it couldn't parse and save a
        // one-off event; Android handed it to the provider (which stores
        // FREQ=HOURLY as an hourly series).
        final calendar = requireCalendar(calendarId);
        final title =
            'Unsupported rule ${DateTime.now().microsecondsSinceEpoch}';
        final start = DateTime.now().add(const Duration(hours: 1));

        await expectLater(
          DeviceCalendarPlusPlatform.instance.createEvent(
            calendar,
            title,
            start,
            start.add(const Duration(minutes: 30)),
            /* isAllDay */ false,
            /* description */ null,
            /* location */ null,
            /* url */ null,
            /* timeZone */ 'UTC',
            /* availability */ 'busy',
            /* recurrenceRule */ rrule,
            /* reminders */ null,
          ),
          throwsA(isA<PlatformException>().having(
            (e) => e.code,
            'code',
            PlatformExceptionCodes.invalidArguments,
          )),
        );
        expect(
          await eventsTitled(plugin, calendar, title,
              start.subtract(const Duration(days: 1)),
              windowDays: 3),
          isEmpty,
          reason: 'a refused rule must leave no event behind',
        );
      });
    }

    // -- Time precision --

    test(
        'a series created at a sub-second start reads back at whole seconds, '
        'its master and its occurrences alike (#165)', () async {
      // iOS stores whole seconds. Android's provider keeps whatever millis
      // DTSTART is given, and on some versions (API 30, Samsung) expands a
      // series' occurrences at whole seconds anyway, so the master and its
      // own occurrences disagreed by the dropped millis.
      final calendar = requireCalendar(calendarId);
      final start = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600) * 1000 + 671,
      );
      final series = await createWeeklySeries(plugin, calendar,
          count: 3, start: start);

      await expectWholeSecondSeries(plugin, calendar, series.eventId, start,
          start.millisecondsSinceEpoch ~/ 1000 * 1000);
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

    test(
        'allEvents re-anchored at a sub-second start reads back at whole '
        'seconds, its master and its occurrences alike (#165)', () async {
      // The #165 path: Android's anchor shift carried the new start's millis
      // into the rewritten DTSTART.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // 10:00 UTC tomorrow: the series is in UTC, so the two-hour move below
      // stays on the same day and keeps the weekday the rule pins.
      final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
      final start =
          DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, 10).toLocal();
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 3, start: start);

      final wholeSecond = start.millisecondsSinceEpoch + 2 * 3600000;
      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        start: DateTime.fromMillisecondsSinceEpoch(wholeSecond + 671),
      );

      await expectWholeSecondSeries(
          plugin, calendarId!, series.eventId, start, wholeSecond);
    });

    test(
        'an occurrence moved to a sub-second start reads back at whole '
        'seconds (#165)', () async {
      // The per-occurrence write path: Android writes the edit as its own
      // detached row, which must be floored like the master's times.
      final calendar = requireCalendar(calendarId);
      final start = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600) * 1000,
      );
      final series = await createWeeklySeries(plugin, calendar,
          count: 3, start: start);
      final occurrences = await occurrencesOf(
          plugin, calendar, series.eventId, start,
          windowDays: 30);
      expect(occurrences, hasLength(3));

      const title = 'Moved Precision #165';
      final wholeSecond =
          occurrences[1].startDate.millisecondsSinceEpoch + 2 * 3600000;
      await plugin.updateEvent(
        instanceId: occurrences[1].instanceId,
        title: title,
        startDate: DateTime.fromMillisecondsSinceEpoch(wholeSecond + 671),
        endDate: DateTime.fromMillisecondsSinceEpoch(wholeSecond + 3600671),
      );

      final moved =
          await eventsTitled(plugin, calendar, title, start, windowDays: 30);
      expect(moved, hasLength(1),
          reason: 'the moved occurrence must appear once');
      expect(moved.single.startDate.millisecondsSinceEpoch, wholeSecond,
          reason: 'the moved occurrence must start at a whole second');
      expect(moved.single.endDate.millisecondsSinceEpoch,
          wholeSecond + 3600000,
          reason: 'the moved occurrence must end at a whole second');
    });

    // Known failure on Android emulator: the emulator's Calendar Provider
    // doesn't propagate the title change to the anchor occurrence after a
    // thisAndFollowing split. Passes on real Android devices.
    test('thisAndFollowing splits so the anchor occurrence carries the change',
        () async {
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
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
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
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

      final start = localMidnight(1);
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
        await expectRefusalLeavesSeriesUntouched(
          plugin,
          calendarId!,
          span,
          (id) => plugin.updateRecurring(
            id,
            span,
            // 30 February: constructible, never generated.
            recurrenceRule:
                Patch.set(YearlyRecurrence(months: [2], daysOfMonth: [30])),
          ),
          throwsInvalidArguments(),
          reason: '$span must refuse a rule that never generates',
        );
      });
    }

    // The typed RecurrenceRule only emits DAILY/WEEKLY/MONTHLY/YEARLY, so
    // these drive the platform layer with the raw string. iOS has always
    // refused a rule EventKit can't express; Android used to hand it to the
    // provider, which kept FREQ=HOURLY as an hourly series.
    for (final span in EventSpan.values) {
      for (final rrule in ['FREQ=HOURLY;COUNT=3', 'NOT-A-RULE']) {
        test(
            'updateRecurring refuses a rule outside DAILY/WEEKLY/MONTHLY/YEARLY '
            '("$rrule") for $span and leaves the series untouched', () async {
          expect(calendarId, isNotNull,
              reason: 'setUpAll must create a calendar');
          await expectRefusalLeavesSeriesUntouched(
            plugin,
            calendarId!,
            span,
            (id) {
              final target = InstanceIdParser.parse(id);
              return DeviceCalendarPlusPlatform.instance.updateRecurring(
                target.eventId,
                target.timestamp,
                span.name,
                recurrenceRule: Patch.set(rrule),
              );
            },
            throwsPlatformCode(PlatformExceptionCodes.invalidArguments),
          );
        });
      }
    }

    // The rule check sits where iOS parses the rule — after the event lookup —
    // so a missing event with a bad rule is notFound on both platforms, not
    // invalidArguments on one of them.
    for (final span in EventSpan.values) {
      test(
          'updateRecurring on a missing event with an unsupported rule is '
          'notFound for $span', () async {
        expect(calendarId, isNotNull,
            reason: 'setUpAll must create a calendar');
        final series = await createWeeklySeries(plugin, calendarId!, count: 4);
        await plugin.deleteRecurring(series.eventId, EventSpan.allEvents);

        await expectLater(
          DeviceCalendarPlusPlatform.instance.updateRecurring(
            series.eventId,
            span == EventSpan.allEvents
                ? null
                : series.start.millisecondsSinceEpoch,
            span.name,
            recurrenceRule: Patch.set('FREQ=HOURLY;COUNT=3'),
          ),
          throwsPlatformCode(PlatformExceptionCodes.notFound),
        );
      });
    }

    test(
        'thisAndFollowing on a one-off event is refused with invalidArguments '
        'and leaves the event untouched (#124)', () async {
      // A one-off has no occurrence apart from itself, so there is no series
      // to split. iOS used to match the timestamp against the event by
      // overlap and edit the whole event; Android refuses.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final event = await createOneOffWithTimestamp(
          plugin, calendarId!, 'One-off split update #124');

      await expectLater(
        plugin.updateRecurring(
          event.instanceId,
          EventSpan.thisAndFollowing,
          title: 'Split #124',
        ),
        throwsInvalidArguments(mentioning: 'not recurring'),
      );

      final after = await plugin.getEvent(event.eventId);
      expect(after, isNotNull, reason: 'a refused update must keep the event');
      expect(after!.title, 'One-off split update #124',
          reason: 'a refused update must leave the event unchanged');
      expect(after.isRecurring, isFalse);
    });

    test(
        'thisAndFollowing with Patch.clear turns the anchor into a standalone '
        'non-recurring event and drops future occurrences (#93)', () async {
      // Issue #93's "this and future" case: split the series at the chosen
      // occurrence, make that occurrence a standalone non-recurring event,
      // and remove every later occurrence. Past occurrences stay in the
      // original series.
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
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

    // Detached occurrences across an update split (#158). iOS's
    // EKSpan.futureEvents save re-parents a detached occurrence whose slot
    // is past the split onto the new series: it keeps its own edits, and the
    // new series skips its slot rather than generating a duplicate there.
    // Which series it ends up on is decided by the slot it replaced, not by
    // where it was moved to, as for the delete path's "... by its original
    // slot" tests. A split that moves the anchor by whole days moves the
    // occurrence and its slot by the same days; one that clears the rule
    // drops it.

    /// The start shift of a [splitAfterDrags] split.
    const splitShift = Duration(hours: 1);

    /// Seeds a daily series, moves each of [drags]' occurrences (`index`) by
    /// its `move`, retitled `'<label> <tag>'` so it can be found, then splits
    /// the series at [3] with a thisAndFollowing update that shifts the start
    /// by [splitShift] and sets the rule [ruleFor] gives for the series, if
    /// any. The series has [count] occurrences. Returns the moved occurrences
    /// and their titles in [drags]' order, and the new series' starts.
    Future<
        ({
          SeededSeries series,
          List<Event> moved,
          List<String> titles,
          String newSeriesId,
          List<int> newStarts,
        })> splitAfterDrags(
      List<(int index, Duration move, String label)> drags, {
      Patch<RecurrenceRule>? Function(SeededSeries series)? ruleFor,
      int count = 10,
    }) async {
      final series = await seedSeries(
        plugin,
        calendarId,
        count: count,
        minOccurrences: count,
      );
      final id = calendarId!;
      final tag = DateTime.now().microsecondsSinceEpoch;
      final moved = <Event>[];
      final titles = <String>[];
      for (final (index, move, label) in drags) {
        final title = '$label $tag';
        titles.add(title);
        moved.add(await moveOccurrence(plugin, id, series, index, move, title));
      }

      final newTitle = 'New series after drags $tag';
      final anchor = series.occurrences[3];
      final newSeriesId = await plugin.updateRecurring(
        anchor.instanceId,
        EventSpan.thisAndFollowing,
        title: newTitle,
        start: anchor.startDate.add(splitShift),
        recurrenceRule: ruleFor?.call(series),
      );
      final newStarts = startsOf(
        await eventsTitled(plugin, id, newTitle, series.start),
      );
      return (
        series: series,
        moved: moved,
        titles: titles,
        newSeriesId: newSeriesId,
        newStarts: newStarts,
      );
    }

    test(
      'thisAndFollowing update carries a detached occurrence past the split '
      'into the new series',
      () async {
        // Even when the split also moves the start, which moves the slot
        // with it. One before the split stays on the old series.
        const withinDay = Duration(hours: 2);
        final split = await splitAfterDrags([
          (6, withinDay, 'Detached past update split'),
          (1, withinDay, 'Detached before update split'),
        ]);
        final series = split.series;
        final id = calendarId!;
        final [pastTitle, beforeTitle] = split.titles;
        final [movedPast, movedBefore] = split.moved;

        // The new series: every slot from the anchor on, shifted, except the
        // detached one's — no duplicate beside it.
        final slot6 = series.occurrences[6].startDate.add(splitShift);
        expect(
          split.newStarts,
          isNot(contains(slot6.millisecondsSinceEpoch)),
          reason: 'the new series must skip the slot of the detached '
              'occurrence it took over, not generate a duplicate there',
        );
        expect(
          split.newStarts,
          containsAll([3, 4, 5, 7, 8].map((i) => series.occurrences[i]
              .startDate
              .add(splitShift)
              .millisecondsSinceEpoch)),
          reason: 'the new series must carry every other slot from the anchor '
              'on, shifted',
        );

        // Both detached occurrences keep their own edits and times.
        await expectDetachedOnce(plugin, id, pastTitle, movedPast, series.start,
            reason: 'the detached occurrence past the split must survive '
                'with its own title and time');
        await expectDetachedOnce(
            plugin, id, beforeTitle, movedBefore, series.start,
            reason: 'the detached occurrence before the split must survive '
                'untouched');

        // Re-parented, not merely kept: deleting the new series takes the
        // detached occurrence past the split with it, and leaves the one
        // before the split on the old series.
        await plugin.deleteRecurring(split.newSeriesId, EventSpan.allEvents);
        expect(await eventsTitled(plugin, id, pastTitle, series.start), isEmpty,
            reason: 'the detached occurrence past the split must belong to '
                'the new series');
        await expectDetachedOnce(
            plugin, id, beforeTitle, movedBefore, series.start,
            reason: 'the detached occurrence before the split must stay on '
                'the old series');
      },
    );

    test(
      'thisAndFollowing update carries an occurrence dragged from past the '
      'split to before it by its original slot',
      () async {
        // [6] moved onto [1]'s day: its slot is past the split, so it goes
        // to the new series, whose slot it keeps standing in for.
        final split = await splitAfterDrags([
          (
            6,
            const Duration(days: -5, hours: 2),
            'Dragged across update split',
          ),
        ]);
        final slot6 = split.series.occurrences[6].startDate
            .add(splitShift)
            .millisecondsSinceEpoch;
        expect(split.newStarts, isNot(contains(slot6)),
            reason: 'the new series must skip [6]\'s slot, which the moved '
                'occurrence stands in for');
        // It sits before the split, so the split's time shift must not
        // move it.
        await expectDetachedOnce(plugin, calendarId!, split.titles.single,
            split.moved.single, split.series.start,
            reason: 'the moved occurrence must survive once, with its own '
                'title at its dragged time');

        await plugin.deleteRecurring(split.newSeriesId, EventSpan.allEvents);
        expect(
            await eventsTitled(
                plugin, calendarId!, split.titles.single, split.series.start),
            isEmpty,
            reason: 'the moved occurrence must belong to the new series, and '
                'go with it');
      },
    );

    test(
      'thisAndFollowing update leaves an occurrence dragged from before the '
      'split to past it by its original slot',
      () async {
        // [1] moved onto [6]'s day: its slot is before the split, so it
        // stays on the old series, and nothing detached stands in for [6].
        final split = await splitAfterDrags([
          (
            1,
            const Duration(days: 5, hours: 2),
            'Dragged across update split',
          ),
        ]);
        final slot6 = split.series.occurrences[6].startDate
            .add(splitShift)
            .millisecondsSinceEpoch;
        expect(split.newStarts, contains(slot6),
            reason: 'the new series must still generate [6]\'s slot, which '
                'nothing detached stands in for');

        await plugin.deleteRecurring(split.newSeriesId, EventSpan.allEvents);
        // The listing half is unverified on Android (#159), as in the
        // delete path's "keeps a detached occurrence by its original slot":
        // the row read still runs.
        await expectDetachedKept(
          plugin,
          calendarId!,
          split.titles.single,
          split.series,
          split.moved.single,
          listed: !Platform.isAndroid,
        );
      },
    );

    test(
      'thisAndFollowing update with a new rule moves a detached occurrence '
      'past the split by the days the anchor moved',
      () async {
        // A weekly rule on the weekday two days after the anchor re-anchors
        // the new series onto that day (#140), and iOS moves each detached
        // occurrence by the same two days, keeping its time of day. The
        // series is stored in UTC, so the weekday is read in UTC (#103).
        // The rule generates [5], [12] and [19]: [10]'s slot moves onto
        // [12], a day the new series generates, so the pairing shows as a
        // skipped slot there; [6]'s moves onto [8], which it doesn't.
        const twoDays = Duration(days: 2);
        final split = await splitAfterDrags(
          [
            (6, const Duration(hours: 2), 'Detached past rule change'),
            (10, const Duration(hours: 2), 'Detached onto new rule slot'),
          ],
          ruleFor: (series) => Patch.set(WeeklyRecurrence(
            daysOfWeek: [
              weekdayOf(series.occurrences[5].startDate.toUtc()),
            ],
            end: const CountEnd(3),
          )),
          count: 12,
        );
        final id = calendarId!;
        final series = split.series;

        // Where [12] would be: the series is stored in UTC, so whole days
        // are exact durations.
        final slot12 =
            series.occurrences[10].startDate.add(twoDays).add(splitShift);
        expect(
          split.newStarts,
          contains(series.occurrences[5].startDate
              .add(splitShift)
              .millisecondsSinceEpoch),
          reason: 'the new series must start on the new rule\'s weekday',
        );
        expect(
          split.newStarts,
          isNot(contains(slot12.millisecondsSinceEpoch)),
          reason: 'the new series must skip the slot [10]\'s detached '
              'occurrence moved onto, not generate a duplicate there',
        );

        for (final (i, title) in split.titles.indexed) {
          expect(
            startsOf(await eventsTitled(plugin, id, title, series.start)),
            [split.moved[i].startDate.add(twoDays).millisecondsSinceEpoch],
            reason: 'the detached occurrence must be listed once, moved by '
                'the days the split moved the anchor, as iOS moves it',
          );
        }

        await plugin.deleteRecurring(split.newSeriesId, EventSpan.allEvents);
        for (final title in split.titles) {
          expect(await eventsTitled(plugin, id, title, series.start), isEmpty,
              reason: 'the detached occurrence must belong to the new series');
        }
      },
    );

    test(
      'thisAndFollowing update that clears the rule drops a detached '
      'occurrence past the split',
      () async {
        // The new event no longer recurs, so no slot is left for the
        // occurrence to stand in: iOS drops it, as a thisAndFollowing delete
        // does. One before the split stays.
        const withinDay = Duration(hours: 2);
        final split = await splitAfterDrags([
          (6, withinDay, 'Detached past rule clear'),
          (1, withinDay, 'Detached before rule clear'),
        ], ruleFor: (_) => const Patch.clear());
        final id = calendarId!;
        final [pastTitle, beforeTitle] = split.titles;
        final [movedPast, movedBefore] = split.moved;

        await expectDetachedGone(
            plugin, id, pastTitle, split.series, movedPast);
        await expectDetachedOnce(
            plugin, id, beforeTitle, movedBefore, split.series.start,
            reason: 'the detached occurrence before the split must survive '
                'untouched');
      },
    );

    test(
      'thisAndFollowing update across a DST change carries a detached '
      'occurrence by calendar days',
      () async {
        // A New York series across the November fall-back, split from before
        // it to after it: the new start is three calendar days on, but three
        // days and an hour of elapsed time. iOS moves the slot and the
        // detached occurrence by the three days, so the new series skips the
        // slot at its own 10:00 instead of generating it beside an
        // occurrence carried an hour off.
        final id = requireCalendar(calendarId);
        final fallBack = nextUsFallBack();
        // 10:00 EDT, three days before the change.
        final start =
            DateTime.utc(fallBack.year, fallBack.month, fallBack.day - 3, 14);
        final tag = DateTime.now().microsecondsSinceEpoch;
        final eventId = await plugin.createEvent(
          calendarId: id,
          title: 'DST series $tag',
          startDate: start,
          endDate: start.add(const Duration(hours: 1)),
          recurrenceRule: const DailyRecurrence(end: CountEnd(12)),
          timeZone: 'America/New_York',
        );
        final occurrences = await occurrencesOf(plugin, id, eventId, start);
        expect(occurrences.length, 12,
            reason: 'the series must expand to every occurrence');
        final SeededSeries series =
            (eventId: eventId, start: start, occurrences: occurrences);
        final title = 'Detached across DST $tag';
        final moved = await moveOccurrence(
            plugin, id, series, 8, const Duration(hours: 2), title);

        // [1] (10:00 EDT) to the day after the change, 10:00 EST.
        final newTitle = 'New series across DST $tag';
        await plugin.updateRecurring(
          occurrences[1].instanceId,
          EventSpan.thisAndFollowing,
          title: newTitle,
          start: DateTime.utc(
              fallBack.year, fallBack.month, fallBack.day + 1, 15),
        );

        // [8] was 10:00 EST, and three calendar days on is 10:00 EST too.
        const threeDays = Duration(days: 3);
        final slot8 = occurrences[8].startDate.add(threeDays);
        final newStarts =
            startsOf(await eventsTitled(plugin, id, newTitle, start));
        expect(newStarts, isNot(contains(slot8.millisecondsSinceEpoch)),
            reason: 'the new series must skip the slot the detached '
                'occurrence stands in for, three calendar days on');
        expect(
          newStarts,
          containsAll([
            slot8.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            slot8.add(const Duration(days: 1)).millisecondsSinceEpoch,
          ]),
          reason: 'the new series must generate the slots either side',
        );
        expect(
          startsOf(await eventsTitled(plugin, id, title, start)),
          [moved.startDate.add(threeDays).millisecondsSinceEpoch],
          reason: 'the detached occurrence must move by three calendar days, '
              'keeping its own time of day',
        );
      },
    );

    // A single-occurrence delete past the split (#158). iOS keeps it
    // deleted in the new series while the split leaves the start where it
    // was; a split that moves the start brings it back, since iOS's deleted
    // date stays at the old time and no longer matches the moved slot. On
    // Android the delete is itself an exception row, a cancelled one, so the
    // detached-occurrence carry decides this and is built to match.
    for (final (shift, outcome, atSlot6, slot6Reason) in [
      (
        Duration.zero,
        'keeps it deleted',
        (int slot) => isNot(contains(slot)),
        'the new series must keep the deleted occurrence past the split '
            'deleted',
      ),
      (
        const Duration(hours: 1),
        'brings it back when the start moves',
        (int slot) => contains(slot),
        'the new series must bring the deleted occurrence back at its '
            'moved slot, as iOS does',
      ),
    ]) {
      test(
        'thisAndFollowing update past a deleted occurrence $outcome',
        () async {
          final series = await seedSeries(
            plugin,
            calendarId,
            minOccurrences: 10,
          );
          final id = calendarId!;
          final tag = DateTime.now().microsecondsSinceEpoch;

          await plugin.deleteEvent(
              instanceId: series.occurrences[6].instanceId);

          final newTitle = 'New series past deleted $tag';
          final anchor = series.occurrences[3];
          await plugin.updateRecurring(
            anchor.instanceId,
            EventSpan.thisAndFollowing,
            title: newTitle,
            start: anchor.startDate.add(shift),
          );

          final newStarts = startsOf(
            await eventsTitled(plugin, id, newTitle, series.start),
          );
          final slot6 =
              series.occurrences[6].startDate.add(shift).millisecondsSinceEpoch;
          expect(newStarts, atSlot6(slot6), reason: slot6Reason);
          expect(
            newStarts,
            containsAll([3, 4, 5, 7, 8].map((i) => series.occurrences[i]
                .startDate
                .add(shift)
                .millisecondsSinceEpoch)),
            reason: 'the new series must carry every other slot from the '
                'anchor on, shifted',
          );
        },
      );
    }

    test('updateEvent with an instance ID edits only the one occurrence',
        () async {
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
      final target = occurrences[4];

      await plugin.updateEvent(
        instanceId: target.instanceId,
        title: 'Just this one',
      );

      // The detached exception must surface once, with the new title, at
      // the targeted moment.
      await expectDetachedOnce(
        plugin, calendarId!, 'Just this one', target, series.start,
        reason: 'listEvents must include the detached exception',
      );

      // The master must still expand into every other occurrence — the
      // earlier ones included (#153) — each with the original title.
      final afterUpdate = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(
        startsOf(afterUpdate),
        startsExcept(occurrences, {4}),
        reason: 'every occurrence but the targeted one must stay on the '
            'series',
      );
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
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
      final target = occurrences[4];

      await expectLater(
        plugin.updateEvent(
          instanceId: target.instanceId,
          startDate: target.startDate.add(const Duration(days: 2)),
        ),
        throwsInvalidArguments(),
      );
    });

    test(
        'updateEvent moving an instance to another day keeps every other '
        'occurrence (#153)', () async {
      // The reporter's shape in #153: a weekly BYDAY series ending on a
      // date, one occurrence moved a day later through its instance ID.
      // The daily-series test above covers the title-only edit.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final anchor = DateTime.now().toUtc().add(const Duration(hours: 1));
      final series = await createWeeklySeries(
        plugin,
        calendarId!,
        title: 'Weekly #153',
        daysOfWeek: [weekdayOf(anchor)],
        start: anchor,
        end: UntilEnd(anchor.add(const Duration(days: 7 * 8 + 1))),
      );
      final eventId = series.eventId;
      final before = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 70);
      expect(before.length, 9, reason: 'the anchor plus eight weekly repeats');
      final target = before[3];
      final movedStart = target.startDate.add(const Duration(days: 1));

      await plugin.updateEvent(
        instanceId: target.instanceId,
        startDate: movedStart,
        endDate: target.endDate.add(const Duration(days: 1)),
      );

      final after = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 70);
      expect(
        startsOf(after),
        startsExcept(before, {3}),
        reason: 'every occurrence but the moved one must stay on the series, '
            'the earlier ones included (#153)',
      );

      // Read by title, the series is the untouched eight plus the moved one
      // on its new day — a day later still sorts into the same slot.
      final titled = await eventsTitled(
          plugin, calendarId!, 'Weekly #153', anchor,
          windowDays: 70);
      expect(
        startsOf(titled),
        startsOf(before)..[3] = movedStart.millisecondsSinceEpoch,
        reason: 'the moved occurrence must appear once, on its new day',
      );
    });

    test(
        'updateEvent on a second occurrence of the same series keeps the '
        'rest (#153)', () async {
      // The steady state after a first per-occurrence edit: the series
      // already carries its key and one exception, and the next exception
      // must join that family rather than disturb it.
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
      final first = occurrences[2];
      final second = occurrences[5];

      await plugin.updateEvent(
          instanceId: first.instanceId, title: 'First #153');
      await plugin.updateEvent(
          instanceId: second.instanceId, title: 'Second #153');

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(
        startsOf(after),
        startsExcept(occurrences, {2, 5}),
        reason: 'every occurrence but the two edited ones must stay on the '
            'series',
      );
      await expectDetachedOnce(
        plugin, calendarId!, 'First #153', first, series.start,
        reason: 'the first edit must survive the second, once, in place',
      );
      await expectDetachedOnce(
        plugin, calendarId!, 'Second #153', second, series.start,
        reason: 'the second edit must detach its own occurrence, once',
      );
    });

    test(
        'updateEvent on a series with a keyless exception from an older '
        'version re-keys it and restores the rest (#153)', () async {
      // Android-only: the upgrade path. Anyone who edited an occurrence with
      // the previous plugin version has #153's on-disk state — a master with
      // no `_sync_id`, an exception with no `original_sync_id`, and the
      // provider's Instances cache holding only the exception. The public
      // API can no longer produce that state, so the example app's seed
      // channel performs the old write; the next edit through the plugin
      // must key the master, re-key the old exception into its family, and
      // bring every untouched occurrence back.
      //
      // The re-key is asserted on the provider's own columns: the
      // incremental re-expansion after the edit honours the old exception
      // with or without it, so the listing alone would pass either way. What
      // the key buys is the provider's full regeneration (a timezone change,
      // a reboot), which matches exceptions to their series by
      // `original_sync_id` — and no test can trigger that.
      final series =
          await seedSeries(plugin, calendarId, minOccurrences: 7);
      // Some providers (Samsung's, #166) stamp a `_sync_id` on every insert,
      // local calendars included, so a master is never keyless there and
      // #153's state can't arise. The #153 behaviour tests above still run
      // on those devices; only this upgrade path is AOSP-specific.
      if ((await readSyncIds(series.eventId))?.syncId != null) {
        markTestSkipped('provider pre-keys local events; #153\'s keyless '
            'state is unreachable here (#166)');
        return;
      }
      final occurrences = series.occurrences;
      final keyless = occurrences[3];
      final rekeying = occurrences[6];

      final exceptionId = await insertKeylessException(
        eventId: series.eventId,
        instanceStart: keyless.startDate,
        instanceEnd: keyless.endDate,
        title: 'Keyless #153',
      );
      expect(exceptionId, isNotEmpty,
          reason: 'the seed must write the old-style exception');
      expect((await readSyncIds(series.eventId))?.syncId, isNull,
          reason: 'the seed must leave the master keyless, #153\'s state');
      expect((await readSyncIds(exceptionId))?.originalSyncId, isNull,
          reason: 'the seed must leave the exception keyless, #153\'s state');

      await plugin.updateEvent(
          instanceId: rekeying.instanceId, title: 'Rekeyed #153');

      final masterKey = (await readSyncIds(series.eventId))?.syncId;
      expect(masterKey, isNotNull, reason: 'the edit must key the master');
      expect((await readSyncIds(exceptionId))?.originalSyncId, masterKey,
          reason: 'the old exception must be re-keyed into the family');

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(
        startsOf(after),
        startsExcept(occurrences, {3, 6}),
        reason: 'keying the master must bring back every occurrence but the '
            'two detached ones',
      );
      await expectDetachedOnce(
        plugin, calendarId!, 'Keyless #153', keyless, series.start,
        reason: 'the old exception must survive the re-key, once, in place',
      );
      await expectDetachedOnce(
        plugin, calendarId!, 'Rekeyed #153', rekeying, series.start,
        reason: 'the new edit must detach its own occurrence, once',
      );
    }, skip: !Platform.isAndroid);

    test('updateEvent refuses a bare recurring-series ID and writes nothing',
        () async {
      // updateEvent acts on one thing (#175): moving a series' start through
      // it used to shift the whole series and drop every earlier occurrence
      // without an error. Series edits go through updateRecurring, so a bare
      // series ID is refused before any write.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before, isNotEmpty);

      await expectLater(
        plugin.updateEvent(
          instanceId: series.eventId,
          title: 'Refused',
          startDate: series.start.add(const Duration(days: 2)),
          endDate: series.start.add(const Duration(days: 2, hours: 1)),
        ),
        throwsInvalidArguments(mentioning: 'updateRecurring'),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(startsOf(after), startsOf(before),
          reason: 'a refused update must leave every occurrence in place');
      expect(after.every((e) => e.title == 'Daily Series'), isTrue,
          reason: 'a refused update must not change any field');
    });

    test('updateRecurring sets and clears reminders across the series',
        () async {
      // reminders is the one field updateEvent had that updateRecurring
      // lacked; with series edits routed through updateRecurring it needs
      // it (#175).
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 4);

      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        reminders: const Patch.set([
          Duration(minutes: 15),
          Duration(hours: 1),
        ]),
      );
      final withReminders = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(withReminders, hasLength(4));
      for (final occurrence in withReminders) {
        expect(occurrence.reminders?.toSet(),
            {const Duration(minutes: 15), const Duration(hours: 1)},
            reason: 'every occurrence must carry the series reminders');
      }

      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        reminders: const Patch.clear(),
      );
      final cleared = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(cleared, hasLength(4));
      for (final occurrence in cleared) {
        expect(occurrence.reminders ?? const <Duration>[], isEmpty,
            reason: 'clearing must remove every occurrence\'s reminders');
      }
    });

    test(
        'updateRecurring thisAndFollowing sets reminders on the new series '
        'only', () async {
      // A rule-keeping split goes through each platform's split path (the
      // new series on Android, EKSpan.futureEvents on iOS), not the
      // allEvents one, so the reminders patch must survive it too (#175).
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 6);
      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(occurrences, hasLength(6));
      final splitMillis = occurrences[3].startDate.millisecondsSinceEpoch;
      const reminders = [Duration(minutes: 15), Duration(hours: 1)];

      final newSeriesId = await plugin.updateRecurring(
        occurrences[3].instanceId,
        EventSpan.thisAndFollowing,
        title: 'Reminded Tail',
        reminders: const Patch.set(reminders),
      );

      final head = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expectTruncatedMaster(head, before: occurrences[3].startDate, count: 3);
      for (final occurrence in head) {
        expect(occurrence.reminders ?? const <Duration>[], isEmpty,
            reason: 'occurrences before the split must keep their (empty) '
                'reminders');
      }

      final tail =
          await occurrencesOf(plugin, calendarId!, newSeriesId, series.start);
      expect(tail, isNotEmpty,
          reason: 'the new series must carry the occurrences from the split');
      expect(tail.first.startDate.millisecondsSinceEpoch, splitMillis,
          reason: 'the new series must start at the split point');
      for (final occurrence in tail) {
        expect(occurrence.reminders?.toSet(), reminders.toSet(),
            reason: 'every occurrence of the new series must carry the '
                'reminders');
      }
    });

    // A rule-clearing split leaves a standalone event at the split point,
    // built field by field on iOS rather than through EKSpan.futureEvents —
    // and it used to drop the occurrence's alarms (#175). Both the patched
    // and the inherited reminders must land on it.
    for (final (label, seriesReminders, patch, expected) in [
      (
        'sets a reminders patch on',
        null,
        const Patch<List<Duration>>.set(
            [Duration(minutes: 15), Duration(hours: 1)]),
        {const Duration(minutes: 15), const Duration(hours: 1)},
      ),
      (
        'keeps the series reminders on',
        const [Duration(minutes: 10), Duration(minutes: 30)],
        null,
        {const Duration(minutes: 10), const Duration(minutes: 30)},
      ),
    ]) {
      test(
          'updateRecurring thisAndFollowing with the rule cleared $label the '
          'standalone it leaves (#175)', () async {
        expect(calendarId, isNotNull,
            reason: 'setUpAll must create a calendar');
        final series = await createDailySeries(plugin, calendarId!,
            count: 6, reminders: seriesReminders);
        final occurrences = await occurrencesOf(
            plugin, calendarId!, series.eventId, series.start);
        expect(occurrences, hasLength(6));
        final splitMillis = occurrences[3].startDate.millisecondsSinceEpoch;

        final standaloneId = await plugin.updateRecurring(
          occurrences[3].instanceId,
          EventSpan.thisAndFollowing,
          recurrenceRule: const Patch.clear(),
          reminders: patch,
        );

        final standalone = await plugin.getEvent(standaloneId);
        expect(standalone, isNotNull);
        expect(standalone!.recurrenceRule, isNull);
        expect(standalone.startDate.millisecondsSinceEpoch, splitMillis,
            reason: 'the standalone must sit at the split point');
        expect(standalone.reminders?.toSet(), expected,
            reason: 'the standalone must carry the split occurrence\'s '
                'reminders');

        final head = await occurrencesOf(
            plugin, calendarId!, series.eventId, series.start);
        expectTruncatedMaster(head,
            before: occurrences[3].startDate, count: 3);
        for (final occurrence in head) {
          expect(occurrence.reminders?.toSet() ?? const <Duration>{},
              (seriesReminders ?? const <Duration>[]).toSet(),
              reason: 'occurrences before the split must keep the series '
                  'reminders');
        }
      });
    }

    test(
        'thisAndFollowing keeps a COUNT series to its total when the series '
        'started more than five years before the split (#124)', () async {
      // A rule-keeping split gives the new series the original COUNT less
      // the occurrences before the split. Android once counted those over a
      // five-year look-back, so an older series under-counted them and the
      // new series over-generated past the original end.
      final calendar = requireCalendar(calendarId);
      final start = DateTime.utc(DateTime.now().year - 7, 1, 15, 12);
      final eventId = await plugin.createEvent(
        calendarId: calendar,
        title: 'Old Yearly Series',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: YearlyRecurrence(end: const CountEnd(10)),
        timeZone: 'UTC',
      );
      const windowDays = 12 * 366;
      final occurrences = await occurrencesOf(plugin, calendar, eventId, start,
          windowDays: windowDays);
      expect(occurrences, hasLength(10),
          reason: 'the yearly series should expand into all 10 occurrences');
      // Eight years in: the start of next year, so the split is in the
      // future and the five-year look-back missed three of the eight.
      final split = occurrences[8];

      final newSeriesId = await plugin.updateRecurring(
        split.instanceId,
        EventSpan.thisAndFollowing,
        title: 'Old Yearly Tail',
      );

      expectTruncatedMaster(
        await occurrencesOf(plugin, calendar, eventId, start,
            windowDays: windowDays),
        before: split.startDate,
        count: 8,
      );
      expect(
        startsOf(await occurrencesOf(plugin, calendar, newSeriesId, start,
            windowDays: windowDays)),
        startsOf(occurrences.sublist(8)),
        reason: 'the new series must carry exactly the occurrences left '
            'after the split, ending where the original series ended',
      );
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

    /// A 6-count weekly Mon/Wed/Fri series stored in UTC, starting at
    /// [start] (Mon 2 Nov 2026 15:00 UTC unless given), and its occurrences.
    Future<({String eventId, DateTime anchor, List<Event> occurrences})>
        createMwfSeries({
      DateTime? start,
    }) async {
      final anchor = start ?? DateTime.utc(2026, 11, 2, 15);
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 6,
          daysOfWeek: [
            DayOfWeek.monday,
            DayOfWeek.wednesday,
            DayOfWeek.friday,
          ],
          start: anchor);
      final occurrences = await occurrencesOf(
          plugin, calendarId!, series.eventId, anchor,
          windowDays: 30);
      return (
        eventId: series.eventId,
        anchor: anchor,
        occurrences: occurrences,
      );
    }

    /// A 3-count yearly series on the 4th Thursday of November, stored in
    /// UTC and anchored on Thu 26 Nov 2026 15:00 UTC.
    Future<({String eventId, DateTime anchor})> createThanksgivingSeries({
      required String title,
    }) async {
      final anchor = DateTime.utc(2026, 11, 26, 15);
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: title,
        startDate: anchor,
        endDate: anchor.add(const Duration(hours: 1)),
        recurrenceRule: YearlyRecurrence.byWeekday(
          months: [11],
          daysOfWeek: [RecurrenceDay(DayOfWeek.thursday, position: 4)],
          end: const CountEnd(3),
        ),
        timeZone: 'UTC',
      );
      return (eventId: eventId, anchor: anchor);
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
      // weekday the rule does not list — an ambiguous move we refuse. The
      // series is stored in UTC, so pin its UTC weekday: east of UTC the
      // local one can leave the start off the rule and the +1-day move on it.
      final startDay = DateTime.now().add(const Duration(hours: 1));
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [weekdayOf(startDay.toUtc())], start: startDay);
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
        throwsInvalidArguments(),
      );
    });

    test('day shift that keeps the weekday but leaves a pinned BYMONTH throws',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Yearly on the 4th Thursday of November, anchored on Thu 26 Nov 2026.
      // +7 days lands on Thu 3 Dec: the weekday holds, but BYMONTH=11 does
      // not, so both platforms must refuse the move without a new rule.
      final (:eventId, :anchor) =
          await createThanksgivingSeries(title: 'Thanksgiving Series');
      final before = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 400);
      expect(before.length, greaterThanOrEqualTo(2),
          reason: 'the yearly series should have expanded into occurrences');

      await expectLater(
        plugin.updateRecurring(
          before.first.instanceId,
          EventSpan.allEvents,
          start: before.first.startDate.add(const Duration(days: 7)),
        ),
        throwsInvalidArguments(),
      );

      final after = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 400);
      expect(
        after.map((e) => e.startDate).toList(),
        before.map((e) => e.startDate).toList(),
        reason: 'a refused move must leave the series as it was',
      );
    });

    test('day shift onto another ordinal of a pinned BYDAY throws', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Yearly on the 4th Thursday of November, anchored on Thu 26 Nov 2026.
      // -7 days lands on Thu 19 Nov: the weekday and month hold, but it is
      // the 3rd Thursday, which the rule doesn't generate (#189).
      final (:eventId, :anchor) =
          await createThanksgivingSeries(title: 'Thanksgiving Ordinal Series');
      final before = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 400);
      expect(before.length, greaterThanOrEqualTo(2),
          reason: 'the yearly series should have expanded into occurrences');

      await expectLater(
        plugin.updateRecurring(
          before.first.instanceId,
          EventSpan.allEvents,
          start: before.first.startDate.subtract(const Duration(days: 7)),
        ),
        throwsInvalidArguments(),
      );

      final after = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 400);
      expect(
        after.map((e) => e.startDate).toList(),
        before.map((e) => e.startDate).toList(),
        reason: 'a refused move must leave the series as it was',
      );
    });

    test(
        'day shift onto another listed weekday of an explicit-BYDAY rule '
        'moves the anchor', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Weekly on Mon/Wed/Fri, anchored on Mon 2 Nov 2026. +2 days lands on
      // Wed 4 Nov, a day the rule generates, so the move needs no new rule.
      final series = await createMwfSeries();
      final before = series.occurrences;
      expect(before.length, 6);

      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: before.first.startDate.add(const Duration(days: 2)),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.anchor,
          windowDays: 30);
      expect(after, isNotEmpty);
      expect(after.first.startDate.toUtc(), DateTime.utc(2026, 11, 4, 15),
          reason: 'the series must now start on the Wednesday');
      expect(
        after.map((e) => e.startDate.toUtc().weekday).toSet(),
        everyElement(
            isIn([DateTime.monday, DateTime.wednesday, DateTime.friday])),
        reason: 'every occurrence must stay on the rule',
      );
    });

    test(
        'day shift of a later occurrence that pushes the series start off an '
        'explicit-BYDAY rule throws', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Weekly on Mon/Wed/Fri, anchored on Mon 2 Nov 2026. Moving the Fri 6
      // Nov occurrence to Mon 9 Nov lands it on a day the rule generates, but
      // an allEvents move shifts the series start by the same +3 days, onto
      // Thu 5 Nov, which it doesn't (#189).
      final series = await createMwfSeries();
      final before = series.occurrences;
      expect(before.length, 6);
      final friday = before[2];
      expect(friday.startDate.toUtc(), DateTime.utc(2026, 11, 6, 15));

      await expectLater(
        plugin.updateRecurring(
          friday.instanceId,
          EventSpan.allEvents,
          start: friday.startDate.add(const Duration(days: 3)),
        ),
        throwsInvalidArguments(),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.anchor,
          windowDays: 30);
      expect(startsOf(after), startsOf(before),
          reason: 'a refused move must leave the series as it was');
    });

    test(
        'thisAndFollowing day shift onto another ordinal of a pinned BYDAY '
        'throws', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Yearly on the 4th Thursday of November, anchored on Thu 26 Nov 2026.
      // Splitting at the Thu 25 Nov 2027 occurrence and moving it -7 days
      // lands the new series on Thu 18 Nov 2027, the 3rd Thursday, which the
      // kept rule doesn't generate (#189).
      final (:eventId, :anchor) = await createThanksgivingSeries(
          title: 'Thanksgiving Ordinal Split Series');
      final before = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 800);
      expect(before.length, 3,
          reason: 'the yearly series should have expanded into occurrences');
      final second = before[1];
      expect(second.startDate.toUtc(), DateTime.utc(2027, 11, 25, 15));

      await expectLater(
        plugin.updateRecurring(
          second.instanceId,
          EventSpan.thisAndFollowing,
          start: second.startDate.subtract(const Duration(days: 7)),
        ),
        throwsInvalidArguments(),
      );

      final after = await occurrencesOf(plugin, calendarId!, eventId, anchor,
          windowDays: 800);
      expect(startsOf(after), startsOf(before),
          reason: 'a refused split must leave the series as it was');
    });

    test(
        'thisAndFollowing day shift onto another listed weekday of an '
        'explicit-BYDAY rule throws', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Weekly on Mon/Wed/Fri. Splitting at Wed 11 Nov 2026 and moving it +2
      // days lands on Fri 13 Nov, a day the rule generates, but EventKit's
      // .futureEvents save detaches the occurrence instead of splitting a
      // series whose rule pins days (#194). Refused on both platforms until
      // iOS can split it; the same move through allEvents is allowed.
      final series = await createMwfSeries();
      final before = series.occurrences;
      expect(before.length, 6);
      final wednesday = before[4];
      expect(wednesday.startDate.toUtc(), DateTime.utc(2026, 11, 11, 15));

      await expectLater(
        plugin.updateRecurring(
          wednesday.instanceId,
          EventSpan.thisAndFollowing,
          start: wednesday.startDate.add(const Duration(days: 2)),
        ),
        throwsInvalidArguments(mentioning: 'pins specific days'),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.anchor,
          windowDays: 30);
      expect(startsOf(after), startsOf(before),
          reason: 'a refused split must leave the series as it was');
    });

    test(
        'time-only shift of a series start the explicit-BYDAY rule does not '
        'generate is allowed', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // A Mon/Wed/Fri series whose start sits on Tue 3 Nov 2026, off its
      // rule, as one anchored by another app can. Retiming that first
      // occurrence +2h on the same Tuesday isn't a day move, so it must not
      // be refused, though the rule doesn't generate the day (#189). iOS
      // lists the off-rule start as the first occurrence; Android's provider
      // may not, and then the retime is of the Wed 4 Nov occurrence, which
      // keeps the stored start on its Tuesday just the same.
      final start = DateTime.utc(2026, 11, 3, 15);
      final series = await createMwfSeries(start: start);
      final before = series.occurrences;
      expect(before, isNotEmpty);
      expect(
        before.first.startDate.toUtc(),
        anyOf(start, DateTime.utc(2026, 11, 4, 15)),
        reason: 'the series lists from its Tuesday start or the Wednesday '
            'after it',
      );

      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: before.first.startDate.add(const Duration(hours: 2)),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, start,
          windowDays: 30);
      expectShifted(before, after, const Duration(hours: 2));
    });

    test('time-only shift on an explicit-BYDAY rule is allowed', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final startDay = DateTime.now().add(const Duration(hours: 1));
      // The series is stored in UTC, so pin its UTC weekday: the local one
      // leaves the start off the rule whenever the two dates differ.
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [weekdayOf(startDay.toUtc())], start: startDay);
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

    // #144: an all-day `start` is the local midnight of the day it means,
    // while Android stores all-day as UTC midnight. The day-move check and
    // the anchor shift must read both as the same calendar day on either
    // side of UTC — the harness runs these at Los Angeles, UTC and Sydney.

    test(
        'all-day start on the same day of an explicit-BYDAY rule is allowed',
        () async {
      final series = await createAllDayWeeklySeriesOnOwnWeekday(
          plugin, calendarId,
          title: 'All-day Same Day');
      final first = series.occurrences.first;

      // Re-passing the occurrence's own day moves nothing, so the rule's
      // pinned weekday can't conflict.
      await plugin.updateRecurring(
        first.instanceId,
        EventSpan.allEvents,
        start: first.startDate,
        title: 'All-day Same Day (renamed)',
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 30);
      expect(startsOf(after), startsOf(series.occurrences),
          reason: 'a same-day start must leave every occurrence in place');
      expect(after.every((e) => e.title == 'All-day Same Day (renamed)'),
          isTrue);
    });

    test(
        'all-day start a day earlier on an explicit-BYDAY series throws '
        'without a new recurrenceRule', () async {
      final series = await createAllDayWeeklySeriesOnOwnWeekday(
          plugin, calendarId,
          title: 'All-day Day Earlier');
      final first = series.occurrences.first;
      final dayBefore = DateTime(first.startDate.year, first.startDate.month,
          first.startDate.day - 1);

      await expectLater(
        plugin.updateRecurring(
          first.instanceId,
          EventSpan.allEvents,
          start: dayBefore,
        ),
        throwsInvalidArguments(),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 30);
      expect(startsOf(after), startsOf(series.occurrences),
          reason: 'a refused day move must leave the series as it was');
    });

    test('all-day start a day later moves every occurrence a calendar day',
        () async {
      final series = await seedSeries(plugin, calendarId,
          create: createAllDayDailySeries, count: 4, minOccurrences: 4);
      final before = series.occurrences;

      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: nextLocalMidnight(before.first.startDate),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(
        startsOf(after),
        startsOneDayLater(before),
        reason: 'each all-day occurrence must move to the next calendar day',
      );
      expect(
        after.map((e) => e.endDate.millisecondsSinceEpoch).toList(),
        before
            .map((e) =>
                nextLocalMidnight(e.endDate.toLocal()).millisecondsSinceEpoch)
            .toList(),
        reason: 'each all-day occurrence must keep its span, its end moving '
            'a calendar day too',
      );
      expect(after.every((e) => e.isAllDay), isTrue);
    });

    test(
        'all-day duration of two days ends each occurrence two calendar days '
        'after its start (#195)', () async {
      // The shape #195 reported: allEvents with start and a whole-day
      // duration. iOS wrote the end as an exclusive midnight onto an event
      // that was already all-day, and EventKit read it as one more day.
      final series = await seedSeries(plugin, calendarId,
          create: (p, c, {count = 3}) =>
              createWeeklySeries(p, c, count: count, isAllDay: true),
          count: 3,
          minOccurrences: 3,
          windowDays: 30);
      final before = series.occurrences;

      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: before.first.startDate,
        duration: const Duration(days: 2),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 30);
      expect(startsOf(after), startsOf(before),
          reason: 'the start was given unchanged');
      expect(
        after.map((e) => e.endDate.millisecondsSinceEpoch).toList(),
        before
            .map((e) => nextLocalMidnight(nextLocalMidnight(e.startDate))
                .millisecondsSinceEpoch)
            .toList(),
        reason: 'each occurrence must run two calendar days, not three',
      );
    });

    test(
        'all-day thisAndFollowing start a day later moves the new series a '
        'calendar day', () async {
      final series = await seedSeries(plugin, calendarId,
          create: createAllDayDailySeries, count: 6, minOccurrences: 6);
      final before = series.occurrences;
      final split = before[2];

      final newSeriesId = await plugin.updateRecurring(
        split.instanceId,
        EventSpan.thisAndFollowing,
        start: nextLocalMidnight(split.startDate),
      );

      expect(
        startsOf(await occurrencesOf(
            plugin, calendarId!, newSeriesId, series.start)),
        startsOneDayLater(before.sublist(2)),
        reason: 'the split occurrence and every later one must move to the '
            'next calendar day',
      );
      expectTruncatedMaster(
        await occurrencesOf(plugin, calendarId!, series.eventId, series.start),
        before: split.startDate,
      );
    });

    // Toggling all-day changes the frame a series' days are read in: the
    // series was stored in UTC, but the all-day start is a local midnight.
    // iOS once snapped the new all-day anchor to UTC midnight, a day early
    // west of UTC, leaving an extra occurrence off the rule's weekday; east
    // of UTC it read the local-midnight target as the previous UTC day and
    // refused the same-day toggle.
    test(
        'toggling a timed explicit-BYDAY series all-day with a same-day start '
        'keeps every occurrence on its calendar day', () async {
      // Local noon is the same date in UTC for offsets from -11 through +12
      // hours, so the weekday the UTC-stored series pins is the local one too.
      final today = localMidnight(2);
      final start = DateTime(today.year, today.month, today.day, 12);
      final series = await seedSeries(
        plugin,
        calendarId,
        count: 4,
        minOccurrences: 4,
        windowDays: 30,
        create: (plugin, calendarId, {int count = 4}) => createWeeklySeries(
            plugin, calendarId,
            title: 'Timed To All-day',
            count: count,
            daysOfWeek: [weekdayOf(start)],
            start: start),
      );
      final before = series.occurrences;
      final first = before.first.startDate.toLocal();

      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        isAllDay: true,
        start: DateTime(first.year, first.month, first.day),
        duration: const Duration(days: 1),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 30);
      expect(after.every((e) => e.isAllDay), isTrue,
          reason: 'every occurrence must be all-day');
      DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
      expect(
        after.map((e) => dayOf(e.startDate.toLocal())).toList(),
        before.map((e) => dayOf(e.startDate.toLocal())).toList(),
        reason: 'each occurrence must stay on its original calendar day',
      );
    });

    // The toggle alone, with no `start`, must still move the stored start
    // into the all-day frame. Android once left the timed DTSTART under
    // ALL_DAY=1, and the provider reads an all-day start as a UTC date, so
    // a start whose UTC date isn't its local one read back a day off
    // (#124).
    test(
        'toggling a timed series all-day with no start keeps every '
        'occurrence on its calendar day', () async {
      // A local time on another UTC date, where the zone allows one: just
      // after midnight east of UTC, just before it west of UTC.
      final day = localMidnight(2);
      final offset = day.timeZoneOffset;
      final start = offset.isNegative
          ? day.add(const Duration(hours: 23, minutes: 30))
          : day.add(const Duration(minutes: 30));
      final series = await seedSeries(
        plugin,
        calendarId,
        count: 4,
        minOccurrences: 4,
        windowDays: 30,
        create: (plugin, calendarId, {int count = 4}) => createWeeklySeries(
            plugin, calendarId,
            title: 'Timed To All-day No Start', count: count, start: start),
      );
      final before = series.occurrences;

      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        isAllDay: true,
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 30);
      expect(after, hasLength(4));
      expect(after.every((e) => e.isAllDay), isTrue,
          reason: 'every occurrence must be all-day');
      DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
      expect(
        after.map((e) => dayOf(e.startDate.toLocal())).toList(),
        before.map((e) => dayOf(e.startDate.toLocal())).toList(),
        reason: 'each occurrence must stay on its original calendar day',
      );
      expect(
        after.map((e) => e.endDate.toLocal()).toList(),
        before
            .map((e) => nextLocalMidnight(dayOf(e.endDate
                .toLocal()
                .subtract(const Duration(milliseconds: 1)))))
            .toList(),
        reason: 'each occurrence must span every day its timed self touched',
      );
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
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;
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
        () async {
      final series = await seedSeries(plugin, calendarId);
      final occurrences = series.occurrences;

      await plugin.deleteEvent(instanceId: occurrences[4].instanceId);

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);

      // The targeted occurrence is gone and every other one survives, the
      // earlier ones included (#153).
      expect(
        startsOf(after),
        startsExcept(occurrences, {4}),
        reason: 'only the one occurrence should be removed',
      );
    });

    test('deleteEvent refuses a bare recurring-series ID and deletes nothing',
        () async {
      // deleteEvent acts on one thing (#175): a series-wide delete has to go
      // through deleteRecurring(allEvents), so a bare series ID — easy to
      // pass by mistake as `event.eventId` — is refused, not a silent
      // whole-series delete.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!);

      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(before, isNotEmpty);

      await expectLater(
        plugin.deleteEvent(instanceId: series.eventId),
        throwsInvalidArguments(mentioning: 'deleteRecurring'),
      );

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(startsOf(after), startsOf(before),
          reason: 'a refused delete must leave every occurrence in place');
    });

    test(
        'thisAndFollowing on a one-off event is refused with invalidArguments '
        'and deletes nothing (#124)', () async {
      // A one-off has no occurrence apart from itself, so there is no series
      // to truncate. iOS used to match the timestamp against the event by
      // overlap and delete it; Android refuses.
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final event = await createOneOffWithTimestamp(
          plugin, calendarId!, 'One-off split delete #124');

      await expectLater(
        plugin.deleteRecurring(event.instanceId, EventSpan.thisAndFollowing),
        throwsInvalidArguments(mentioning: 'not recurring'),
      );

      final after = await plugin.getEvent(event.eventId);
      expect(after, isNotNull, reason: 'a refused delete must keep the event');
      expect(after!.title, 'One-off split delete #124');
    });

    test('deleteRecurring allEvents removes the detached occurrences too',
        () async {
      // An occurrence edited through its instance ID becomes a detached
      // exception row. Deleting the series must take it along — on a local
      // Android calendar the provider stops cascading once the series has
      // the `_sync_id` the #153 fix gives it, so the plugin cascades itself.
      final series = await seedSeries(plugin, calendarId);

      Future<List<Event>> detached() =>
          eventsTitled(plugin, calendarId!, 'Detached #153', series.start);

      await detachOccurrence(plugin, calendarId!, series, 4, 'Detached #153');

      await plugin.deleteRecurring(series.eventId, EventSpan.allEvents);

      final after = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start);
      expect(after, isEmpty, reason: 'the whole series should be gone');
      expect(await detached(), isEmpty,
          reason: 'deleting the series must remove its detached occurrence');
    });
    test(
      'thisAndFollowing removes a detached occurrence past the split',
      () async {
        // An occurrence edited on its own is a detached exception, not part
        // of the master's expansion. Truncating the master's rule alone would
        // leave it behind as an orphan; iOS's EKSpan.futureEvents removes it,
        // so Android must too.
        final series = await seedSeries(
          plugin,
          calendarId,
          minOccurrences: 8,
        );
        final id = calendarId!;
        final tag = DateTime.now().microsecondsSinceEpoch;

        // Detach one occurrence on each side of the split (anchor at [3]) by
        // moving it two hours within its own day: [6] must go, [1] must stay.
        const withinDay = Duration(hours: 2);
        final pastTitle = 'Detached past split $tag';
        final beforeTitle = 'Detached before split $tag';
        final movedPast = await moveOccurrence(
          plugin,
          id,
          series,
          6,
          withinDay,
          pastTitle,
        );
        final movedBefore = await moveOccurrence(
          plugin,
          id,
          series,
          1,
          withinDay,
          beforeTitle,
        );

        final anchor = series.occurrences[3];
        await plugin.deleteRecurring(
          anchor.instanceId,
          EventSpan.thisAndFollowing,
        );
        final after = await occurrencesOf(
          plugin,
          id,
          series.eventId,
          series.start,
        );
        expectMasterSplit(
          after,
          before: anchor.startDate,
          keeps: [
            series.occurrences[0].startDate,
            series.occurrences[2].startDate,
          ],
        );
        await expectDetachedGone(plugin, id, pastTitle, series, movedPast);
        await expectDetachedKept(plugin, id, beforeTitle, series, movedBefore);
      },
    );

    test(
      'thisAndFollowing keeps a detached occurrence by its original slot',
      () async {
        // Which side of the split a detached occurrence falls on is decided by
        // the slot it replaced in the series, not by where it was moved to:
        // iOS's EKSpan.futureEvents goes by the occurrence date, and Android's
        // ORIGINAL_INSTANCE_TIME bound is built to match. So an occurrence
        // dragged from before the split to after it survives the split.
        final series = await seedSeries(
          plugin,
          calendarId,
          minOccurrences: 8,
        );
        final id = calendarId!;
        final title =
            'Detached forward ${DateTime.now().microsecondsSinceEpoch}';

        // Move [2] onto [7]'s day, offset by two hours so it can't be confused
        // with the master's own [7].
        final moved = await moveOccurrence(
          plugin,
          id,
          series,
          2,
          const Duration(days: 5, hours: 2),
          title,
        );

        // iOS lists a detached occurrence under the master's ID, so the moved
        // copy would read as the master extending past the split; it is
        // asserted on its own below.
        final anchor = series.occurrences[3];
        await plugin.deleteRecurring(
          anchor.instanceId,
          EventSpan.thisAndFollowing,
        );
        final movedMillis = moved.startDate.millisecondsSinceEpoch;
        final after =
            (await occurrencesOf(plugin, id, series.eventId, series.start))
                .where((e) => e.startDate.millisecondsSinceEpoch != movedMillis)
                .toList();
        expectMasterSplit(
          after,
          before: anchor.startDate,
          keeps: [
            series.occurrences[0].startDate,
            series.occurrences[1].startDate,
          ],
        );
        // The listing half is skipped on Android for the emulator's sake: its
        // Calendar Provider drops the moved copy from the Instances cache once
        // the master's rule ends before it, although the row is intact (the
        // row read proves it). Physical Android does list it — verified on a
        // Galaxy A10 / API 30 with this assertion switched on (#159) — so the
        // gate documents an emulator quirk, not a platform contract.
        await expectDetachedKept(
          plugin,
          id,
          title,
          series,
          moved,
          listed: !Platform.isAndroid,
        );
      },
    );

    test(
      'thisAndFollowing removes a detached occurrence by its original slot',
      () async {
        // The other half of the slot rule: an occurrence dragged from after
        // the split to before it goes with "this and following", because the
        // slot it replaced is past the split.
        final series = await seedSeries(
          plugin,
          calendarId,
          minOccurrences: 8,
        );
        final id = calendarId!;
        final title = 'Detached back ${DateTime.now().microsecondsSinceEpoch}';

        // Move [6] onto [1]'s day, offset by two hours so it can't be confused
        // with the master's own [1].
        final moved = await moveOccurrence(
          plugin,
          id,
          series,
          6,
          const Duration(days: -5, hours: 2),
          title,
        );

        final anchor = series.occurrences[3];
        await plugin.deleteRecurring(
          anchor.instanceId,
          EventSpan.thisAndFollowing,
        );
        final after = await occurrencesOf(
          plugin,
          id,
          series.eventId,
          series.start,
        );
        expectMasterSplit(
          after,
          before: anchor.startDate,
          keeps: [
            series.occurrences[0].startDate,
            series.occurrences[1].startDate,
            series.occurrences[2].startDate,
          ],
        );
        await expectDetachedGone(plugin, id, title, series, moved);
      },
    );

    test(
      'thisAndFollowing splits at a detached occurrence\'s own slot',
      () async {
        // The boundary of the slot rule: the anchor occurrence itself was
        // edited on its own. Its slot is exactly the split, so it goes with
        // "this and following" — the ORIGINAL_INSTANCE_TIME bound is inclusive
        // (`>=`) to match. The split is anchored by the master's instance ID
        // for that slot as listed before the edit; the detached copy lists
        // under its own row ID, which carries no occurrence timestamp.
        //
        // Android only: iOS answers `deleteRecurring(master@slot)` for a slot
        // that has been detached with notFound, so the boundary cannot be
        // reached through the public API there (a split-path divergence for
        // #124, not this PR's).
        final series = await seedSeries(
          plugin,
          calendarId,
          minOccurrences: 8,
        );
        final id = calendarId!;
        final title =
            'Detached at anchor ${DateTime.now().microsecondsSinceEpoch}';

        final anchor = series.occurrences[3];
        final moved = await moveOccurrence(
          plugin,
          id,
          series,
          3,
          const Duration(hours: 2),
          title,
        );

        await plugin.deleteRecurring(
          anchor.instanceId,
          EventSpan.thisAndFollowing,
        );
        final after = await occurrencesOf(
          plugin,
          id,
          series.eventId,
          series.start,
        );
        expectMasterSplit(
          after,
          before: anchor.startDate,
          keeps: [
            series.occurrences[0].startDate,
            series.occurrences[1].startDate,
            series.occurrences[2].startDate,
          ],
        );
        await expectDetachedGone(plugin, id, title, series, moved);
      },
      skip: Platform.isAndroid
          ? false
          : 'iOS: anchoring a split on a detached slot is notFound (#124)',
    );
  });
}
