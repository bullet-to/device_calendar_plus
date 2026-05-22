import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
      if (calendarId == null) return;

      final rule = roundtrip(const DailyRecurrence(end: CountEnd(5)));
      final result = await rule;

      expect(result, isNotNull);
      expect(result, isA<DailyRecurrence>());
      expect((result!.end as CountEnd).count, 5);
    });

    test('Weekly recurrence roundtrip', () async {
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

      final result = await roundtrip(YearlyRecurrence(
        end: CountEnd(5),
      ));

      expect(result, isNotNull);
      expect(result, isA<YearlyByDate>());
      expect((result!.end as CountEnd).count, 5);
    });

    test('Monthly by weekday - 2nd Tuesday roundtrip', () async {
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

      final result = await roundtrip(const DailyRecurrence(end: CountEnd(30)));

      expect(result, isNotNull);
      expect(result!.end, isA<CountEnd>());
      expect((result.end as CountEnd).count, 30);
    });

    // -- UNTIL edge case roundtrips --

    test('UNTIL date-only roundtrip', () async {
      if (calendarId == null) return;

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
      if (calendarId == null) return;

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
      if (calendarId == null) return;

      final result = await roundtrip(const DailyRecurrence());

      expect(result, isNotNull);
      expect(result, isA<DailyRecurrence>());
      expect(result!.end, isNull);
    });

    // -- rruleString preservation --

    test('rruleString preserves platform RRULE', () async {
      if (calendarId == null) return;

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

    /// Creates a daily recurring event, returning its ID and start date.
    Future<({String eventId, DateTime start})> createDailySeries({
      int count = 10,
    }) async {
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Daily Series',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: DailyRecurrence(end: CountEnd(count)),
        timeZone: 'UTC',
      );
      return (eventId: eventId, start: start);
    }

    /// Lists the occurrences of [eventId] around [start], in date order.
    Future<List<Event>> occurrencesOf(String eventId, DateTime start) async {
      final events = await plugin.listEvents(
        start.subtract(const Duration(days: 1)),
        start.add(const Duration(days: 14)),
        calendarIds: [calendarId!],
      );
      return events.where((e) => e.eventId == eventId).toList();
    }

    test('allEvents changes the recurrence rule for the whole series',
        () async {
      if (calendarId == null) return;
      final series = await createDailySeries();

      final result = await plugin.updateRecurring(
        series.eventId,
        EventUpdateSpan.allEvents,
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
      expect(updated.recurrenceRule, isA<WeeklyRecurrence>());
    });

    test('allEvents with Patch.clear removes recurrence', () async {
      if (calendarId == null) return;
      final series = await createDailySeries();

      await plugin.updateRecurring(
        series.eventId,
        EventUpdateSpan.allEvents,
        recurrenceRule: const Patch.clear(),
      );

      final updated = await plugin.getEvent(series.eventId);
      expect(updated, isNotNull);
      expect(updated!.isRecurring, isFalse);
      expect(updated.recurrenceRule, isNull);
    });

    test('thisAndFollowing splits so the anchor occurrence carries the change',
        () async {
      if (calendarId == null) return;
      final series = await createDailySeries(count: 10);

      final occurrences = await occurrencesOf(series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6),
          reason: 'the daily series should have expanded into occurrences');
      final splitPoint = occurrences[4];
      final splitMillis = splitPoint.startDate.millisecondsSinceEpoch;

      await plugin.updateRecurring(
        splitPoint.instanceId,
        EventUpdateSpan.thisAndFollowing,
        title: 'Split Tail',
      );

      final after = await plugin.listEvents(
        series.start.subtract(const Duration(days: 1)),
        series.start.add(const Duration(days: 14)),
        calendarIds: [calendarId!],
      );

      // The anchor occurrence itself must carry the change — "this and
      // following" includes the named occurrence.
      final atSplit = after
          .where((e) => e.startDate.millisecondsSinceEpoch == splitMillis)
          .toList();
      expect(atSplit, isNotEmpty,
          reason: 'an occurrence should still exist at the split point');
      expect(atSplit.first.title, 'Split Tail',
          reason: 'the anchor occurrence must receive the change');

      // Occurrences before the split keep the original title.
      final before =
          after.where((e) => e.startDate.millisecondsSinceEpoch < splitMillis);
      expect(before, isNotEmpty);
      expect(before.every((e) => e.title == 'Daily Series'), isTrue,
          reason: 'occurrences before the split must be untouched');
    });

    test('thisAndFollowing can change the rule from the split point onward',
        () async {
      if (calendarId == null) return;
      final series = await createDailySeries(count: 10);

      final occurrences = await occurrencesOf(series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final splitPoint = occurrences[4];

      final newSeriesId = await plugin.updateRecurring(
        splitPoint.instanceId,
        EventUpdateSpan.thisAndFollowing,
        recurrenceRule: Patch.set(const WeeklyRecurrence(end: CountEnd(3))),
      );

      final newSeries = await plugin.getEvent(newSeriesId);
      expect(newSeries, isNotNull);
      expect(newSeries!.recurrenceRule, isA<WeeklyRecurrence>());
    });

    test('thisInstance edits only the one occurrence', () async {
      if (calendarId == null) return;
      final series = await createDailySeries(count: 10);

      final occurrences = await occurrencesOf(series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final target = occurrences[4];
      final targetMillis = target.startDate.millisecondsSinceEpoch;

      await plugin.updateRecurring(
        target.instanceId,
        EventUpdateSpan.thisInstance,
        title: 'Just this one',
      );

      final after = await plugin.listEvents(
        series.start.subtract(const Duration(days: 1)),
        series.start.add(const Duration(days: 14)),
        calendarIds: [calendarId!],
      );

      // Exactly one occurrence changed — the one at the target time.
      final changed = after.where((e) => e.title == 'Just this one').toList();
      expect(changed.length, 1,
          reason: 'only the targeted occurrence should change');
      expect(changed.first.startDate.millisecondsSinceEpoch, targetMillis);

      // The rest of the series keeps the original title.
      final unchanged = after.where((e) => e.title == 'Daily Series').toList();
      expect(unchanged.length, greaterThanOrEqualTo(8),
          reason: 'the rest of the series must be untouched');
    });
  });
}
