import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

// The shared fixtures for tests that arrange a recurring series and read it
// back: creating one, listing its occurrences, and the arrange steps and
// assertions the per-occurrence tests share. Imported by recurrence_test.dart,
// recurrence_read_test.dart and tombstone_test.dart.

/// A seeded series: its event ID and start, and its occurrences as listed
/// right after it was created — the baseline a per-occurrence test compares
/// against.
typedef SeededSeries = ({
  String eventId,
  DateTime start,
  List<Event> occurrences,
});

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

/// Creates a weekly recurring event titled [title], starting at [start] (one
/// hour from now by default, stored in UTC) and ending per [end] (`count`
/// weekly occurrences by default). The recurring weekday is the start's
/// weekday unless [daysOfWeek] is given. Returns the event ID and the start
/// time.
Future<({String eventId, DateTime start})> createWeeklySeries(
  DeviceCalendar plugin,
  String calendarId, {
  String title = 'Weekly Series',
  int count = 5,
  RecurrenceEnd? end,
  List<DayOfWeek>? daysOfWeek,
  DateTime? start,
}) async {
  start ??= DateTime.now().add(const Duration(hours: 1));
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: title,
    startDate: start,
    endDate: start.add(const Duration(hours: 1)),
    recurrenceRule:
        WeeklyRecurrence(daysOfWeek: daysOfWeek, end: end ?? CountEnd(count)),
    timeZone: 'UTC',
  );
  return (eventId: eventId, start: start);
}

/// The [DayOfWeek] of [d]: `DateTime.weekday` is 1-based from Monday, as
/// [DayOfWeek.values] is 0-based from Monday.
DayOfWeek weekdayOf(DateTime d) => DayOfWeek.values[d.weekday - 1];

/// Lists the calendar's events matching [test] over a window wide enough to
/// capture a whole series (a day before [start] to [windowDays] after), in
/// date order.
Future<List<Event>> eventsInWindow(
  DeviceCalendar plugin,
  String calendarId,
  DateTime start,
  int windowDays,
  bool Function(Event) test,
) async {
  final events = await plugin.listEvents(
    start.subtract(const Duration(days: 1)),
    start.add(Duration(days: windowDays)),
    calendarIds: [calendarId],
  );
  return events.where(test).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

/// Lists the occurrences of `eventId` in the calendar, in date order.
Future<List<Event>> occurrencesOf(
  DeviceCalendar plugin,
  String calendarId,
  String eventId,
  DateTime start, {
  int windowDays = 14,
}) =>
    eventsInWindow(
        plugin, calendarId, start, windowDays, (e) => e.eventId == eventId);

/// Lists the events titled [title] in the calendar over the same window as
/// [occurrencesOf], in date order. This is how a detached occurrence is
/// found: `updateEvent` returns no ID for one and the platforms disagree on
/// what it would be, so a title unique to the test is the handle.
Future<List<Event>> eventsTitled(
  DeviceCalendar plugin,
  String calendarId,
  String title,
  DateTime start, {
  int windowDays = 14,
}) =>
    eventsInWindow(
        plugin, calendarId, start, windowDays, (e) => e.title == title);

/// The start instants of [events], for comparing two listings occurrence by
/// occurrence.
List<int> startsOf(Iterable<Event> events) =>
    events.map((e) => e.startDate.millisecondsSinceEpoch).toList();

/// The start instants of [events] except those at [indexes]: an earlier
/// listing with some occurrences detached, in whatever order the indexes are
/// named.
List<int> startsExcept(List<Event> events, Set<int> indexes) => startsOf(
    events.indexed.where((e) => !indexes.contains(e.$1)).map((e) => e.$2));

/// Asserts the occurrence detached as [title] is listed exactly once, at
/// [at]'s start, over the same window as [occurrencesOf].
Future<void> expectDetachedOnce(
  DeviceCalendar plugin,
  String calendarId,
  String title,
  Event at,
  DateTime start, {
  required String reason,
  int windowDays = 14,
}) async {
  expect(
    startsOf(await eventsTitled(plugin, calendarId, title, start,
        windowDays: windowDays)),
    [at.startDate.millisecondsSinceEpoch],
    reason: reason,
  );
}

/// The arrange step the per-occurrence tests share: a daily series of ten
/// with its occurrences listed, at least [minOccurrences] of them. Checks the
/// group's calendar exists first.
Future<SeededSeries> seedDailySeries(
  DeviceCalendar plugin,
  String? calendarId, {
  int minOccurrences = 6,
}) async {
  expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
  final series = await createDailySeries(plugin, calendarId!, count: 10);
  final occurrences =
      await occurrencesOf(plugin, calendarId, series.eventId, series.start);
  expect(occurrences.length, greaterThanOrEqualTo(minOccurrences));
  return (
    eventId: series.eventId,
    start: series.start,
    occurrences: occurrences,
  );
}

/// The other arrange step the per-occurrence tests share: edits [series]'
/// occurrence at [index] through its instance ID, detaching it under
/// [title], and checks it is listed exactly once before the test goes on to
/// delete around it. Returns the detached occurrence's event ID as listed —
/// on Android, the exception row's own `_ID`.
Future<String> detachOccurrence(
  DeviceCalendar plugin,
  String calendarId,
  SeededSeries series,
  int index,
  String title,
) async {
  await plugin.updateEvent(
    eventId: series.occurrences[index].instanceId,
    title: title,
  );
  final detached = await eventsTitled(plugin, calendarId, title, series.start);
  expect(
    detached,
    hasLength(1),
    reason: 'the edited occurrence must be detached before the delete',
  );
  return detached.single.eventId;
}
