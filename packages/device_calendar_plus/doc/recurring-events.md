# Recurring events

## Creating a recurring event

Pass a `RecurrenceRule` to `createEvent`. The rule types are sealed classes, so
the compiler ensures you handle every case.

```dart
// Daily for 30 occurrences.
DailyRecurrence(end: CountEnd(30))

// Every 2 weeks on Monday and Friday.
WeeklyRecurrence(
  interval: 2,
  daysOfWeek: [DayOfWeek.monday, DayOfWeek.friday],
)
```

Monthly and yearly default to day-of-month; use `.byWeekday` for weekday
patterns:

```dart
MonthlyRecurrence(daysOfMonth: [1, 15])                // 1st and 15th
MonthlyRecurrence.byWeekday(                            // 2nd Tuesday
  daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
)
MonthlyRecurrence.byWeekday(                            // last Friday
  daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
)
YearlyRecurrence(months: [12], daysOfMonth: [25])      // Christmas
```

End conditions are a count, a date, or omitted (forever):

```dart
DailyRecurrence(end: CountEnd(10))
DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 12, 31)))
DailyRecurrence()
```

## Reading a rule back

`event.recurrenceRule` gives the typed model. For RRULE features the typed model
doesn't cover, `rruleString` preserves the original platform string:

```dart
final rule = event?.recurrenceRule;
if (rule is MonthlyByWeekday) {
  print(rule.daysOfWeek);
}
print(rule?.rruleString); // e.g. "FREQ=MONTHLY;BYDAY=2TU;COUNT=12"
```

## Occurrences and IDs

`listEvents` expands a series into one `Event` per occurrence. Each shares the
same `eventId` but has a distinct `instanceId` (format `eventId@timestamp`) that
pins the occurrence. Pass `instanceId` to act on a single occurrence; pass the
bare `eventId` to act on the whole series. The instance ID is unstable — it
changes if the occurrence moves — so re-fetch after edits.

## Editing a series

`updateRecurring` edits a series — its rule, its time-of-day or duration, or any
field across occurrences. It takes an `EventSpan`:

- `EventSpan.allEvents` — the whole series follows the change.
- `EventSpan.thisAndFollowing` — split the series: the occurrence you pass and
  every later one carry the change; earlier ones are untouched. Requires an
  instance ID with a timestamp.

```dart
// Move a nightshift series from 11 PM to 1 AM the next day (day + time move
// together, measured in the event's timezone, so DST-safe).
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  start: DateTime(2024, 3, 19, 1, 0),
);

// Change every occurrence to 90 minutes.
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  duration: Duration(minutes: 90),
);

// Change the rule, or stop recurring entirely.
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  recurrenceRule: Patch.set(WeeklyRecurrence(end: CountEnd(10))),
);
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  recurrenceRule: Patch.clear(), // becomes a single non-recurring event
);

// Split: this occurrence and later ones move; returns the new series' ID.
final newSeriesId = await plugin.updateRecurring(
  event.instanceId,
  EventSpan.thisAndFollowing,
  start: DateTime(2024, 3, 18, 15, 0),
  duration: Duration(hours: 1),
);
```

`updateRecurring` returns the affected scope's event ID — the same ID for
`allEvents`, the new series' ID for `thisAndFollowing`.

### Moving the day of a pinned rule

`start` moves the series anchor. For rules whose day is implied by the start
(`DailyRecurrence()`, `WeeklyRecurrence()`, `MonthlyRecurrence()`), the pattern
just follows the anchor.

For rules that pin a day explicitly (`WeeklyRecurrence(daysOfWeek: …)`,
`MonthlyRecurrence(daysOfMonth: …)`, positional rules like "2nd Tuesday"),
moving the day with `start` alone throws
`DeviceCalendarException(invalidArguments)` — because moving one day of a
multi-day rule is ambiguous (Mon of Mon/Wed/Fri → Tue could mean Tue/Wed/Fri or
Tue/Thu/Sat). Pass the new `recurrenceRule` in the same call to say what the
pattern should become. Time-only, duration-only, and whole-week shifts never
throw. Watch the converse: a cross-midnight retime (11 PM → 1 AM) rolls the date
forward, so it changes the weekday and will throw too.

### Customised occurrences

Editing a series is best-effort with respect to occurrences the user had
individually moved or deleted. Customisations before a `thisAndFollowing` split
point survive; customisations at or after the split point (or anywhere, for
`allEvents`) may be reset.

## Deleting a series

`deleteRecurring` takes the same `EventSpan`:

```dart
await plugin.deleteRecurring(event.instanceId, EventSpan.allEvents);
await plugin.deleteRecurring(event.instanceId, EventSpan.thisAndFollowing);
```

`thisAndFollowing` requires an instance ID with a timestamp; `allEvents` accepts
either. All series edits require full access.
