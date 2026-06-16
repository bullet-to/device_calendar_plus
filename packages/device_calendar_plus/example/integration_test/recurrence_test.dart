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

/// Creates a weekly recurring event starting one hour from now (UTC), with
/// `count` weekly occurrences. The recurring weekday is the start's weekday
/// unless [daysOfWeek] is given. Returns the event ID and the start time.
Future<({String eventId, DateTime start})> createWeeklySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 5,
  List<DayOfWeek>? daysOfWeek,
}) async {
  final start = DateTime.now().add(const Duration(hours: 1));
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
      final detachedOccurrences = await occurrencesOf(
          plugin, calendarId!, standaloneId, series.start);
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
  // together (issue #103). The series is created in UTC, so wall-clock deltas
  // equal absolute deltas and the assertions are timezone-independent.
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
      final before =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(before.length, greaterThanOrEqualTo(3));

      // Move the whole series two hours later.
      final newStart = before.first.startDate.add(const Duration(hours: 2));
      await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: newStart,
      );

      final after =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
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

    test('allEvents start shift changes day and time together (crosses midnight)',
        () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 6);
      final before =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
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
      final before =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
      expect(before.length, greaterThanOrEqualTo(6));
      final splitIndex = 4;
      final splitMillis = before[splitIndex].startDate.millisecondsSinceEpoch;

      final newSeriesId = await plugin.updateRecurring(
        before[splitIndex].instanceId,
        EventSpan.thisAndFollowing,
        start: before[splitIndex].startDate.add(const Duration(hours: 2)),
      );

      // Occurrences before the split stay put under the original series.
      final remainingMaster =
          await occurrencesOf(plugin, calendarId!, series.eventId, series.start);
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

    const weekdays = [
      DayOfWeek.monday,
      DayOfWeek.tuesday,
      DayOfWeek.wednesday,
      DayOfWeek.thursday,
      DayOfWeek.friday,
      DayOfWeek.saturday,
      DayOfWeek.sunday,
    ];

    test('day shift on an explicit-BYDAY rule without a rule throws', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      // Pin the rule to the start's own weekday so the +1-day shift lands on a
      // weekday the rule does not list — an ambiguous move we refuse.
      final startDay = DateTime.now().add(const Duration(hours: 1));
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [weekdays[startDay.weekday - 1]]);
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
          count: 4, daysOfWeek: [weekdays[startDay.weekday - 1]]);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before, isNotEmpty);

      // +2h same calendar day — weekday unchanged, so no rule conflict.
      final newStart = before.first.startDate.add(const Duration(hours: 2));
      // Guard against the +2h accidentally crossing midnight in this run.
      if (newStart.weekday == before.first.startDate.weekday) {
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
      final oldDay = weekdays[startDay.weekday - 1];
      final newDay = weekdays[startDay.weekday % 7]; // next weekday
      final series = await createWeeklySeries(plugin, calendarId!,
          count: 4, daysOfWeek: [oldDay]);
      final before = await occurrencesOf(
          plugin, calendarId!, series.eventId, series.start,
          windowDays: 45);
      expect(before, isNotEmpty);

      // Passing the new rule alongside start resolves the ambiguity.
      final result = await plugin.updateRecurring(
        before.first.instanceId,
        EventSpan.allEvents,
        start: before.first.startDate.add(const Duration(days: 1)),
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
      expect(after.every((e) => e.startDate.weekday == startDay.weekday % 7 + 1),
          isTrue,
          reason: 'every occurrence should now fall on the new weekday');
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
}
