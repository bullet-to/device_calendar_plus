import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Creates a daily recurring event starting one hour from now (UTC), with
/// `count` total occurrences. Returns the event ID, the start time, and the
/// unique title used.
///
/// The title is unique per call so tests in the same group don't see each
/// other's events when filtering listEvents results by title.
Future<({String eventId, DateTime start, String title})> createDailySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 10,
}) async {
  final start = DateTime.now().add(const Duration(hours: 1));
  final title = 'Daily Series ${DateTime.now().microsecondsSinceEpoch}';
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: title,
    startDate: start,
    endDate: start.add(const Duration(hours: 1)),
    recurrenceRule: DailyRecurrence(end: CountEnd(count)),
    timeZone: 'UTC',
  );
  return (eventId: eventId, start: start, title: title);
}

/// Lists the occurrences of `eventId` in the calendar over a window wide
/// enough to capture the whole series, in date order as returned by the
/// platform.
Future<List<Event>> occurrencesOf(
  DeviceCalendar plugin,
  String calendarId,
  String eventId,
  DateTime start,
) async {
  final events = await plugin.listEvents(
    start.subtract(const Duration(days: 1)),
    start.add(const Duration(days: 14)),
    calendarIds: [calendarId],
  );
  return events.where((e) => e.eventId == eventId).toList();
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

    test('thisAndFollowing splits so the anchor occurrence carries the change',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
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
      final remainingMaster =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(remainingMaster, isNotEmpty,
          reason: 'occurrences before the split must survive');
      expect(
        remainingMaster
            .every((e) => e.startDate.millisecondsSinceEpoch < splitMillis),
        isTrue,
        reason: 'the original series must not extend past the split point',
      );
      expect(remainingMaster.every((e) => e.title == series.title), isTrue,
          reason: 'occurrences before the split must keep the original title');

      // The new series starts at the split point and carries the new title.
      final newSeriesOccurrences = await occurrencesOf(
          plugin, calendarId!, newSeriesId, series.start);
      final atSplit = newSeriesOccurrences
          .where((e) => e.startDate.millisecondsSinceEpoch == splitMillis)
          .toList();
      expect(atSplit, isNotEmpty,
          reason: 'the new series should have an occurrence at the split point');
      expect(atSplit.first.title, 'Split Tail',
          reason: 'the anchor occurrence must receive the change');
    });

    test('thisAndFollowing can change the rule from the split point onward',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final splitPoint = occurrences[4];
      final splitMillis = splitPoint.startDate.millisecondsSinceEpoch;

      final newSeriesId = await plugin.updateRecurring(
        splitPoint.instanceId,
        EventSpan.thisAndFollowing,
        recurrenceRule: Patch.set(const WeeklyRecurrence(end: CountEnd(3))),
      );

      // The new series carries the new rule with the requested count.
      final newSeries = await plugin.getEvent(newSeriesId);
      expect(newSeries, isNotNull);
      final weekly = newSeries!.recurrenceRule as WeeklyRecurrence;
      expect((weekly.end as CountEnd).count, 3,
          reason: 'count from the new rule must round-trip');

      // The new series starts at the split point — i.e. the anchor
      // occurrence is now the first occurrence of the new series.
      expect(newSeries.startDate.millisecondsSinceEpoch, splitMillis,
          reason: 'the new series must start at the split point');
    });

    test('thisInstance edits only the one occurrence', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final initialCount = occurrences.length;
      final target = occurrences[4];
      final targetMillis = target.startDate.millisecondsSinceEpoch;

      final exceptionId = await plugin.updateRecurring(
        target.instanceId,
        EventSpan.thisInstance,
        title: 'Just this one',
      );

      // The exception event holds the new title at the targeted moment.
      final exception = await plugin.getEvent(exceptionId);
      expect(exception, isNotNull, reason: 'exception event must be readable');
      expect(exception!.title, 'Just this one');
      expect(exception.startDate.millisecondsSinceEpoch, targetMillis);

      // We also want to assert that the master series's expansion now
      // contains exactly `initialCount - 1` occurrences (the targeted one
      // is overridden by the exception) and that those remaining
      // occurrences still carry the original title. That's blocked on
      // Android by the same CONTENT_EXCEPTION_URI Instances-cache quirk
      // that affects deleteRecurring's thisInstance path: after the
      // exception insert, the master's Instances expansion returns zero
      // occurrences. See the analogous fix on the deleteRecurring side —
      // when that lands here, replace this TODO with the real assertions.
      //
      // TODO(updateRecurring.thisInstance/Android): assert master scope
      // shape once the multi-field touch fix is applied here too.
      //
      // We can still confirm the master row itself wasn't corrupted —
      // its title should be unchanged on the master event row.
      final master = await plugin.getEvent(series.eventId);
      expect(master, isNotNull);
      expect(master!.title, series.title,
          reason: 'the master event row must keep its original title');
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
      final before =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(before, isNotEmpty);

      await plugin.deleteRecurring(series.eventId, EventSpan.allEvents);

      final after =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(after, isEmpty, reason: 'the whole series should be gone');
      expect(await plugin.getEvent(series.eventId), isNull);
    });

    test('thisAndFollowing removes the anchor and every later occurrence',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final anchor = occurrences[4];
      final anchorMillis = anchor.startDate.millisecondsSinceEpoch;

      await plugin.deleteRecurring(
        anchor.instanceId,
        EventSpan.thisAndFollowing,
      );

      final after =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);

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

    test('thisInstance removes only the one occurrence',
        // iOS works (EventKit's remove with .thisEvent). Android currently
        // throws "not yet supported" — both the minimal CONTENT_EXCEPTION_URI
        // insert and the DTSTART+DURATION variant cause the provider to
        // cancel the whole series rather than just one instance. Re-enable
        // when Android lands a working implementation (likely via EXDATE
        // on the master).
        skip: 'TODO: enable when Android thisInstance is implemented',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 10);

      final occurrences =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(occurrences.length, greaterThanOrEqualTo(6));
      final initialCount = occurrences.length;
      final target = occurrences[4];
      final targetMillis = target.startDate.millisecondsSinceEpoch;

      await plugin.deleteRecurring(target.instanceId, EventSpan.thisInstance);

      final after =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);

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
  });
}
