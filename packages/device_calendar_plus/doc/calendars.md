# Calendars and sources

## List calendars

```dart
final calendars = await plugin.listCalendars();
for (final calendar in calendars) {
  print('${calendar.name} (${calendar.readOnly ? "read-only" : "writable"})');
  if (calendar.isPrimary) print('  ⭐ primary');
  // colorHex is the raw "#RRGGBB"; color is a parsed Flutter Color.
  if (calendar.color != null) { /* use for theming */ }
}
```

## List sources

Sources are the accounts that own calendars (iCloud, Google, local, Exchange…).
Use them to pick where a new calendar lives.

```dart
final sources = await plugin.listSources();
final writable = sources.firstWhere((s) => s.supportsCalendarCreation);
```

> On Android, only sources that already have at least one calendar are
> returned. A freshly-added account won't appear until its first calendar
> exists.

## Create a calendar

```dart
// Picks a sensible default account.
final id = await plugin.createCalendar(name: 'My Calendar');

// With a color.
final colored = await plugin.createCalendar(name: 'Work', colorHex: '#FF5733');

// Targeting a specific account.
final scopedIos = await plugin.createCalendar(
  name: 'Work',
  platformOptions: CreateCalendarOptionsIos(sourceId: writable.id),
);
final scopedAndroid = await plugin.createCalendar(
  name: 'Work',
  platformOptions: CreateCalendarOptionsAndroid(
    accountName: writable.accountName,
    accountType: writable.accountType,
  ),
);
```

Returns the new calendar's ID.

Only a source with `supportsCalendarCreation` can hold a new calendar — on iOS
that's the local source and iCloud, on Android the local account type. Any
other source or account type throws `DeviceCalendarException(readOnly)` before
anything is written.

`colorHex` takes `#RRGGBB` (the `#` is optional). Anything else throws
`ArgumentError`.

## Update a calendar

```dart
await plugin.updateCalendar(calendarId, name: 'Q3 Planning', colorHex: '#3366FF');
```

Pass `name`, `colorHex`, or both. Passing neither is a no-op. Throws
`DeviceCalendarException(readOnly)` for a calendar that can't be modified (see
below).

## Delete a calendar

```dart
await plugin.deleteCalendar(calendarId);
```

Deletes the calendar and all of its events. Throws
`DeviceCalendarException(readOnly)` for a calendar that can't be deleted. On
Android that's one whose access level is below contributor — exactly the
calendars `listCalendars` reports as `readOnly`. On iOS it's any calendar
`listCalendars` reports as `readOnly` (Birthdays, subscribed feeds, holiday
calendars), plus ones EventKit marks immutable: their properties can't be
edited and they can't be deleted even though events can still be added (an
account's default calendar, say). So on iOS `Calendar.readOnly == false` isn't
a guarantee that a rename or delete will be accepted.

Creating, updating, and deleting calendars all require full access.
