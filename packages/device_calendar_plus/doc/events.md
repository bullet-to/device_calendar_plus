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

## Event color (read-only)

`Event.colorHex` is the event's custom color as `#RRGGBB` (with a parsed
`Event.color` getter). It is read-only and platform-specific:

- **Android** reads the event's custom color (`EVENT_COLOR`), e.g. one set in
  Google Calendar. It's `null` when the event just uses its calendar's color.
- **iOS** always reports `null` — EventKit has no per-event color.

There is no write support; `createEvent`/`updateEvent` don't accept a color.
For the calendar's own color, see [calendars.md](calendars.md).

## Update

`updateEvent` and `deleteEvent` act on one thing: a one-off event, or one
occurrence of a recurring series. Pass `event.instanceId`. For a one-off event
it equals `event.eventId`; for an occurrence it names just that occurrence,
which detaches as an exception and is edited alone.

```dart
await plugin.updateEvent(instanceId: event.instanceId, title: 'New title');

// description, location, and url take a Patch:
// omit = leave unchanged, Patch.set(v) = change, Patch.clear() = remove.
await plugin.updateEvent(
  instanceId: event.instanceId,
  location: Patch.set('Room B'),
  description: Patch.clear(),
);

// Switch between timed and all-day.
await plugin.updateEvent(instanceId: event.instanceId, isAllDay: true);

// Edit only this occurrence of a recurring event (it detaches as an exception).
await plugin.updateEvent(
  instanceId: event.instanceId,
  startDate: DateTime(2024, 3, 21, 15, 0),
  endDate: DateTime(2024, 3, 21, 16, 0),
);
```

Switching `isAllDay` reinterprets the times: timed → all-day strips the start
and end to midnight; all-day → timed starts them at midnight. Setting `timeZone`
reinterprets the wall-clock time rather than preserving the instant. Passing no
fields is a no-op.

To edit a recurring **series**, use `updateRecurring`
([recurring-events.md](recurring-events.md)). A bare series ID
(`event.eventId` of a recurring event) is refused by `updateEvent` and
`deleteEvent` with `DeviceCalendarError.invalidArguments`, and nothing is
written. That stops an easy mistake: moving a series' start through
`updateEvent` would drop every earlier occurrence without an error.

## Delete

```dart
// A one-off event, or only this occurrence of a recurring one.
await plugin.deleteEvent(instanceId: event.instanceId);

// The whole series.
await plugin.deleteRecurring(event.eventId, EventSpan.allEvents);
```

Reading, updating, and deleting require full access; creating works with
write-only.
