# Native UI

The plugin can hand off to the OS's own calendar screens for viewing, editing,
and creating events. Each call completes when the modal is dismissed and does
not report back what the user changed — edits are saved directly by the OS.

One modal shows at a time. Calling either method while a modal is still up
throws `DeviceCalendarException(operationFailed)` straight away and leaves the
open one alone, so guard your button against double taps or catch it. The same
error comes back when there's nothing to present from (no Android Activity, no
iOS window).

## View or edit an existing event

```dart
// Open the view screen (the user can still tap Edit from here).
await plugin.showEventModal(event.instanceId);

// Open directly in the editor.
await plugin.showEventModal(event.instanceId, edit: true);
```

`edit` only controls whether the modal *starts* in the editor — the view screen
is not read-only, it always offers an edit affordance.

> **Android `edit: true` caveat:** some calendar apps honor it inconsistently —
> notably, Google Calendar ignores it for an existing event and opens a blank
> new-event editor instead, while the stock calendar lands in the editor as
> expected. For a dependable edit flow, use the view modal (`edit: false`) and
> let the user tap Edit. iOS is unaffected.

## Create an event in the native editor

Useful when you want the user to review before saving, or to add attendees
(which can't be done programmatically).

```dart
// Blank editor.
await plugin.showCreateEventModal();

// Pre-filled.
await plugin.showCreateEventModal(
  title: 'Team Meeting',
  startDate: DateTime.now().add(const Duration(hours: 1)),
  endDate: DateTime.now().add(const Duration(hours: 2)),
  location: 'Conference Room A',
);
```

All fields are optional.

`showCreateEventModal` needs **no calendar permission** on Android or iOS 17+ —
the system editor saves the event with its own access. That makes it a handy
fallback when the user has denied access: a silent `createEvent` when granted,
the pre-filled native form otherwise. On iOS 16 and below the editor runs
in-process and requires full access.

`showEventModal` requires full access, and throws
`DeviceCalendarException(notFound)` for an event that doesn't exist (a deleted
one, say) without opening anything.
