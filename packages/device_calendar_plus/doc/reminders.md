# Reminders

Reminders are relative alarms that fire a fixed lead time **before** an event
starts. Each is a `Duration` of lead time.

```dart
// 15 minutes and 1 hour before start.
await plugin.createEvent(
  calendarId: calendarId,
  title: 'Standup',
  startDate: start,
  endDate: end,
  reminders: [Duration(minutes: 15), Duration(hours: 1)],
);
```

Reminders are minute-granular: a sub-minute `Duration` rounds to the nearest
minute. A zero `Duration` (at start) is allowed; a negative one throws
`ArgumentError`. Omitting `reminders` creates the event with none.

Read them back from `event.reminders`.

## Updating reminders

`updateEvent` takes a `Patch<List<Duration>>` — `Patch.set` replaces the whole
set, `Patch.clear` removes all reminders:

```dart
await plugin.updateEvent(
  eventId: event.eventId,
  reminders: Patch.set([Duration(minutes: 30)]),
);

await plugin.updateEvent(
  eventId: event.eventId,
  reminders: Patch.clear(),
);
```
