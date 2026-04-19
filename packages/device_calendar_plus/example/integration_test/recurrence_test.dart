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

    /// Helper: create event, read it back, return the recurrence rule.
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

      // Read back events in a window around the start date
      final events = await plugin.listEvents(
        start.subtract(const Duration(hours: 2)),
        end.add(const Duration(hours: 2)),
        calendarIds: [calendarId!],
      );

      final matchingEvents = events.where((e) => e.eventId == eventId).toList();
      expect(matchingEvents, isNotEmpty,
          reason: 'Event should be found in the date range');

      final event = matchingEvents.first;
      expect(event.isRecurring, isTrue, reason: 'Event should be recurring');

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

    test('Monthly by weekday - last Friday roundtrip', () async {
      if (calendarId == null) return;

      final result = await roundtrip(MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
        end: CountEnd(12),
      ));

      expect(result, isNotNull);
      expect(result, isA<MonthlyByWeekday>());
      final monthly = result as MonthlyByWeekday;
      expect(monthly.daysOfWeek[0].day, DayOfWeek.friday);
      expect(monthly.daysOfWeek[0].position, -1);
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

    test('Yearly by weekday - last Monday of May roundtrip', () async {
      if (calendarId == null) return;

      final result = await roundtrip(YearlyRecurrence.byWeekday(
        months: [5],
        daysOfWeek: [RecurrenceDay(DayOfWeek.monday, position: -1)],
        end: CountEnd(5),
      ));

      expect(result, isNotNull);
      expect(result, isA<YearlyByWeekday>());
      final yearly = result as YearlyByWeekday;
      expect(yearly.months, [5]);
      expect(yearly.daysOfWeek[0].day, DayOfWeek.monday);
      expect(yearly.daysOfWeek[0].position, -1);
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

    test('Monthly BYSETPOS - first weekday of month roundtrip', () async {
      if (calendarId == null) return;

      final result = await roundtrip(MonthlyRecurrence.byWeekday(
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.tuesday),
          RecurrenceDay(DayOfWeek.wednesday),
          RecurrenceDay(DayOfWeek.thursday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [1],
        end: CountEnd(6),
      ));

      expect(result, isNotNull);
      expect(result, isA<MonthlyByWeekday>());
      final monthly = result as MonthlyByWeekday;
      expect(monthly.setPositions, [1]);
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

    test('UNTIL with non-UTC timezone event roundtrip', () async {
      if (calendarId == null) return;

      final untilDate = DateTime.utc(2027, 6, 15);
      final result = await roundtrip(
        DailyRecurrence(end: UntilEnd(untilDate)),
        timeZone: 'America/New_York',
      );

      expect(result, isNotNull);
      expect(result!.end, isA<UntilEnd>());
      final until = (result.end as UntilEnd).until;
      // The calendar date should be preserved regardless of timezone
      expect(until.year, 2027);
      expect(until.month, 6);
      expect(until.day, 15);
    });

    test('UNTIL near DST boundary roundtrip', () async {
      if (calendarId == null) return;

      // March 9, 2025 is near US DST spring-forward
      final untilDate = DateTime.utc(2027, 3, 9);
      final result = await roundtrip(
        DailyRecurrence(end: UntilEnd(untilDate)),
        timeZone: 'America/New_York',
      );

      expect(result, isNotNull);
      expect(result!.end, isA<UntilEnd>());
      final until = (result.end as UntilEnd).until;
      expect(until.year, 2027);
      expect(until.month, 3);
      expect(until.day, 9);
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
}
