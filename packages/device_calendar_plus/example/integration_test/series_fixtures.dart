import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

// The shared fixtures for tests that arrange a recurring series and read it
// back: creating one, listing its occurrences, and the arrange steps and
// assertions the per-occurrence tests share.

/// The group's calendar, checked to exist: setUpAll must have created it.
String requireCalendar(String? calendarId) {
  expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
  return calendarId!;
}

/// A series factory: creates a recurring event of [count] occurrences in the
/// calendar and returns its event ID and start: [createDailySeries],
/// [createAllDayDailySeries], [createMidUtcDayDailySeries], or a closure
/// over [createWeeklySeries].
typedef SeriesFactory = Future<({String eventId, DateTime start})> Function(
  DeviceCalendar plugin,
  String calendarId, {
  int count,
});

/// Tomorrow (by the UTC date) at 14:00 UTC: the start for a series stored
/// in UTC whose test moves it, or its occurrences, by a few hours and
/// expects that to stay a time-only move. A shift of under ten hours either
/// way stays on the start's UTC date. Seeded at "an hour from now" instead,
/// a run between 22:00 and 23:00 UTC let an hour's shift cross UTC
/// midnight, and the tests failed only in that hour (#222).
DateTime midUtcDayTomorrow() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day + 1, 14);
}

/// A daily series factory that starts at [midUtcDayTomorrow], for
/// [seedSeries].
Future<({String eventId, DateTime start})> createMidUtcDayDailySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 10,
}) =>
    createDailySeries(plugin, calendarId,
        count: count, start: midUtcDayTomorrow());

/// A seeded series: its event ID and start, and its occurrences as listed
/// right after it was created — the baseline a per-occurrence test compares
/// against.
typedef SeededSeries = ({
  String eventId,
  DateTime start,
  List<Event> occurrences,
});

/// Creates a daily recurring event starting at [start] (one hour from now
/// by default), stored in UTC, with `count` total occurrences and any
/// [reminders]. Returns the event ID and the start time.
Future<({String eventId, DateTime start})> createDailySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 10,
  List<Duration>? reminders,
  DateTime? start,
}) async {
  start ??= DateTime.now().add(const Duration(hours: 1));
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: 'Daily Series',
    startDate: start,
    endDate: start.add(const Duration(hours: 1)),
    recurrenceRule: DailyRecurrence(end: CountEnd(count)),
    timeZone: 'UTC',
    reminders: reminders,
  );
  return (eventId: eventId, start: start);
}

/// Creates an all-day daily recurring event starting tomorrow (local
/// midnight, DST-safe) and spanning its day, with `count` total occurrences.
/// Returns the event ID and the start.
Future<({String eventId, DateTime start})> createAllDayDailySeries(
  DeviceCalendar plugin,
  String calendarId, {
  int count = 10,
}) async {
  final start = localMidnight(1);
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: 'All-day Daily Series',
    startDate: start,
    endDate: nextLocalMidnight(start),
    isAllDay: true,
    recurrenceRule: DailyRecurrence(end: CountEnd(count)),
  );
  return (eventId: eventId, start: start);
}

/// Creates a weekly recurring event titled [title], starting at [start] and
/// ending per [end] (`count` weekly occurrences by default). The recurring
/// weekday is the start's weekday unless [daysOfWeek] is given. Timed by
/// default: [duration] long (an hour), starting one hour from now, stored in
/// UTC. With [isAllDay] it spans its day instead, and [start] defaults to
/// tomorrow's local midnight. Returns the event ID and the start time.
Future<({String eventId, DateTime start})> createWeeklySeries(
  DeviceCalendar plugin,
  String calendarId, {
  String title = 'Weekly Series',
  int count = 5,
  RecurrenceEnd? end,
  List<DayOfWeek>? daysOfWeek,
  DateTime? start,
  Duration duration = const Duration(hours: 1),
  bool isAllDay = false,
}) async {
  start ??= isAllDay
      ? localMidnight(1)
      : DateTime.now().add(const Duration(hours: 1));
  final eventId = await plugin.createEvent(
    calendarId: calendarId,
    title: title,
    startDate: start,
    endDate: isAllDay ? nextLocalMidnight(start) : start.add(duration),
    isAllDay: isAllDay,
    recurrenceRule:
        WeeklyRecurrence(daysOfWeek: daysOfWeek, end: end ?? CountEnd(count)),
    timeZone: isAllDay ? null : 'UTC',
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

/// The end instants of [events], the counterpart of [startsOf].
List<int> endsOf(Iterable<Event> events) =>
    events.map((e) => e.endDate.millisecondsSinceEpoch).toList();

/// The instants of [days]: [startsOf] for the dates a test expects, so the
/// two compare as lists.
List<int> millisOf(Iterable<DateTime> days) =>
    days.map((d) => d.millisecondsSinceEpoch).toList();

/// The start instants of [events], each moved to the next local midnight:
/// what an all-day listing reads after its series moves a calendar day later.
List<int> startsOneDayLater(Iterable<Event> events) => events
    .map((e) =>
        nextLocalMidnight(e.startDate.toLocal()).millisecondsSinceEpoch)
    .toList();

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

/// Asserts the occurrence of [series] at [index] came off it under [title]
/// after an edit flipped its all-day flag, and returns it: the one event
/// listed under [title], over the window [seedWeeklySeries] listed the
/// series in, with every other occurrence still on the series. [title] may
/// be the series' own, as it is when the edit leaves the title alone: the
/// master is filtered out by its event ID.
Future<Event> expectDetachedOffSeries(
  DeviceCalendar plugin,
  String calendarId,
  SeededSeries series,
  int index,
  String title,
) async {
  final detached = (await eventsTitled(plugin, calendarId, title, series.start,
          windowDays: 30))
      .where((e) => e.eventId != series.eventId)
      .toList();
  expect(detached, hasLength(1),
      reason: 'the detached occurrence must be listed once');
  expect(
    startsOf(await occurrencesOf(
        plugin, calendarId, series.eventId, series.start,
        windowDays: 30)),
    startsExcept(series.occurrences, {index}),
    reason: 'every other occurrence must stay on the series',
  );
  return detached.single;
}

/// Asserts a `thisAndFollowing` split at [before] left the master's earlier
/// occurrences ([keeps], by start) and nothing of it on or after the split.
/// Pins no count on purpose: what the master lists in a detached
/// occurrence's place varies by platform, so only the slots that must
/// survive are named.
void expectMasterSplit(
  List<Event> remaining, {
  required DateTime before,
  required Iterable<DateTime> keeps,
}) {
  expect(
    startsOf(remaining).toSet(),
    containsAll(millisOf(keeps)),
    reason: 'the occurrences before the split must survive on the master',
  );
  expect(
    remaining.every((e) => e.startDate.isBefore(before)),
    isTrue,
    reason: 'the original series must not extend past the split point',
  );
}

/// The arrange step the per-occurrence tests share: a series of [count] made
/// by [create] (a timed daily one, by default) with its occurrences listed
/// over [windowDays], at least [minOccurrences] of them. Checks the group's
/// calendar exists first.
Future<SeededSeries> seedSeries(
  DeviceCalendar plugin,
  String? calendarId, {
  SeriesFactory create = createDailySeries,
  int count = 10,
  int minOccurrences = 6,
  int windowDays = 14,
}) async {
  final id = requireCalendar(calendarId);
  final series = await create(plugin, id, count: count);
  final occurrences = await occurrencesOf(
      plugin, id, series.eventId, series.start,
      windowDays: windowDays);
  expect(
    occurrences.length,
    greaterThanOrEqualTo(minOccurrences),
    reason: 'the series must expand to at least $minOccurrences occurrences',
  );
  return (
    eventId: series.eventId,
    start: series.start,
    occurrences: occurrences,
  );
}

/// A weekly series titled [title] with [count] occurrences, seeded with them
/// listed over 30 days — all of them, unless [minOccurrences] asks for fewer.
/// The arrange of the occurrence all-day flip tests (#203, #210, #212),
/// whose bodies are then the one `updateEvent` call under test and its
/// assertions, and of the all-day duration and series toggle tests (#144,
/// #195, #208). Timed from [start] (an hour from now by default) for
/// [duration], or all-day from the next local midnight when [isAllDay]; on
/// the start's weekday unless [daysOfWeek] pins others. Checks the group's
/// calendar exists first.
Future<SeededSeries> seedWeeklySeries(
  DeviceCalendar plugin,
  String? calendarId, {
  String title = 'Weekly Series',
  bool isAllDay = false,
  DateTime? start,
  Duration duration = const Duration(hours: 1),
  List<DayOfWeek>? daysOfWeek,
  int count = 4,
  int? minOccurrences,
}) =>
    seedSeries(
      plugin,
      calendarId,
      count: count,
      minOccurrences: minOccurrences ?? count,
      windowDays: 30,
      create: (plugin, calendarId, {int count = 4}) => createWeeklySeries(
          plugin, calendarId,
          title: title,
          count: count,
          daysOfWeek: daysOfWeek,
          start: start,
          duration: duration,
          isAllDay: isAllDay),
    );

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
    instanceId: series.occurrences[index].instanceId,
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
