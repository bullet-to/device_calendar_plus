# Events

## Create

```dart
final eventId = await plugin.createEvent(
  calendarId: calendarId, // omit to use the device's default calendar
  title: 'Team Meeting',
  startDate: DateTime(2024, 3, 20, 14, 0),
  endDate: DateTime(2024, 3, 20, 15, 0),
);

// All-day event.
await plugin.createEvent(
  calendarId: calendarId,
  title: 'Conference',
  startDate: DateTime(2024, 3, 20),
  endDate: DateTime(2024, 3, 21),
  isAllDay: true,
);

// With optional fields.
await plugin.createEvent(
  calendarId: calendarId,
  title: 'Project Kickoff',
  startDate: DateTime(2024, 3, 20, 10, 0),
  endDate: DateTime(2024, 3, 20, 12, 0),
  description: 'Quarterly kickoff',
  location: 'Conference Room A',
  url: 'https://example.com/meeting',
  timeZone: 'America/New_York',
  availability: EventAvailability.busy,
  reminders: [Duration(minutes: 15)],
);
```

Omitting `calendarId` writes to the device's default calendar. See
[recurring-events.md](recurring-events.md) for `recurrenceRule` and
[reminders.md](reminders.md) for `reminders`.

## List

```dart
final now = DateTime.now();
final events = await plugin.listEvents(
  now,
  now.add(const Duration(days: 30)),
  calendarIds: ['cal-1', 'cal-2'], // optional; omit for all calendars
);
```

The range is half-open `[start, end)` — an event starting exactly at `end` is
excluded. Recurring events are expanded into one `Event` per occurrence; see
[recurring-events.md](recurring-events.md) for how occurrences are identified.

## Get one

```dart
final event = await plugin.getEvent(id); // null if not found
```

`id` may be an event ID (the master, for a recurring series) or an instance ID
(a specific occurrence). See [recurring-events.md](recurring-events.md).

## Update

Pass an event ID to update the event (the whole series when recurring), or an
instance ID to detach and edit one occurrence.

```dart
await plugin.updateEvent(eventId: event.eventId, title: 'New title');

// description, location, and url take a Patch:
// omit = leave unchanged, Patch.set(v) = change, Patch.clear() = remove.
await plugin.updateEvent(
  eventId: event.eventId,
  location: Patch.set('Room B'),
  description: Patch.clear(),
);

// Switch between timed and all-day.
await plugin.updateEvent(eventId: event.eventId, isAllDay: true);

// Edit only this occurrence of a recurring event (it detaches as an exception).
await plugin.updateEvent(
  eventId: event.instanceId,
  startDate: DateTime(2024, 3, 21, 15, 0),
  endDate: DateTime(2024, 3, 21, 16, 0),
);
```

Switching `isAllDay` reinterprets the times: timed → all-day strips the start
and end to midnight; all-day → timed starts them at midnight. Setting `timeZone`
reinterprets the wall-clock time rather than preserving the instant. Passing no
fields is a no-op. To edit a recurring **series**, use `updateRecurring`
([recurring-events.md](recurring-events.md)).

## Delete

```dart
// The event (the whole series, if recurring).
await plugin.deleteEvent(eventId: event.eventId);

// Only this occurrence.
await plugin.deleteEvent(eventId: event.instanceId);
```

Reading, updating, and deleting require full access; creating works with
write-only.
