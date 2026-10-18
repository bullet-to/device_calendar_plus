# Platform-only options

Most of the API works the same on Android and iOS. Where one platform can do
something the other genuinely can't, the write goes through a typed
`android:` or `ios:` parameter instead of a shared field:

| Method                                         | `android:`                  | `ios:`               |
| ---------------------------------------------- | --------------------------- | -------------------- |
| `createEvent`                                  | `EventOptionsAndroid`       | —                    |
| `updateEvent`, `updateRecurring`               | `EventUpdateOptionsAndroid` | —                    |
| `createCalendar`                               | `CalendarOptionsAndroid`    | `CalendarOptionsIos` |

Each one applies only on its own platform and is silently ignored on the
other, so shared code can pass both without a `Platform.isAndroid` check:

```dart
await plugin.createCalendar(
  name: 'Work',
  android: CalendarOptionsAndroid(
    accountName: source.accountName,
    accountType: source.accountType,
  ),
  ios: CalendarOptionsIos(sourceId: source.id),
);
```

## No parity, on purpose

Fields inside these types are that platform's own, with its own semantics
and value sets. They're not mapped onto, normalised against, or reconciled
with anything similar on the other platform. `EventStatusAndroid` is
Android's `STATUS` column exactly as `CalendarContract.Events` defines it,
not the shared `EventStatus` enum wearing an Android hat. If iOS ever grows
something similar, it gets its own type with its own meaning.

What you won't find is a shared field that quietly does nothing on one
platform. If you passed it, it was written, or it was in the other
platform's options.

## Event status (Android)

Android stores an event status (`STATUS_TENTATIVE`, `STATUS_CONFIRMED`,
`STATUS_CANCELED`) you can write. EventKit's `EKEvent.status` is read-only,
so on iOS it stays read-only, and the shared `Event.status` keeps reading it
on both platforms as before.

```dart
// Create.
final id = await plugin.createEvent(
  title: 'Maybe lunch',
  startDate: start,
  endDate: end,
  android: const EventOptionsAndroid(status: EventStatusAndroid.tentative),
);

// Update. Leave it out (or null) to keep the event's status.
await plugin.updateEvent(
  instanceId: id,
  android: const EventUpdateOptionsAndroid(
    status: EventStatusAndroid.confirmed,
  ),
);
```

Quirks worth knowing:

- **Defaults to confirmed.** `createEvent` without a status writes
  `STATUS_CONFIRMED`, as it always has.
- **No clear.** Android's Calendar Provider can't write a `NULL` status to
  an existing event (it throws on one), so an update sets a status or leaves
  it, and there's no `Patch.clear`. An event another app wrote without one
  still reads as `EventStatus.none`, and edits that don't set one keep it
  that way.
- **Synced calendars may overwrite it.** On a Google or Exchange calendar the
  account's server owns the event; it can replace the status on the next
  sync.
- **Series follow Android's rows.** `updateRecurring` with
  `EventSpan.allEvents` sets the series' status; with
  `EventSpan.thisAndFollowing` it sets the new series' (the original keeps
  its own). Without a status in the call, the new series carries the
  original's. Occurrences edited on their own keep their own status either
  way.
- **One occurrence.** `updateEvent` on an instance ID sets that occurrence
  alone. Edit an occurrence without passing a status and it keeps the
  series'.
- **`canceled` hides recurring events.** Android's Calendar Provider expands
  no occurrences for a cancelled series, and reads a cancelled occurrence as
  a deleted one. So `canceled` on a series (`createEvent` with a rule,
  `updateRecurring` on either span) takes its occurrences out of
  `listEvents`, leaving only the ones edited on their own, and on one
  occurrence (`updateEvent` with its instance ID) takes that occurrence out,
  just as `deleteEvent` would. `getEvent` still finds a cancelled series by
  its ID. A cancelled one-off event is still listed, with
  `EventStatus.canceled`.
- **iOS ignores it.** On iOS a call whose only change is `android:` writes
  nothing (and `updateRecurring` returns the ID you passed, splitting
  nothing).

## Calendar account (Android) and source (iOS)

`CalendarOptionsAndroid` picks the account a new calendar is created under
(`accountName`, defaulting to `"local"`, and `accountType`, defaulting to
`ACCOUNT_TYPE_LOCAL`). `CalendarOptionsIos` picks the `EKSource` by
`sourceId`. See [Calendars and sources](calendars.md#create-a-calendar).

## Migrating `createCalendar`

`createCalendar`'s `platformOptions:` parameter is gone, along with
`CreateCalendarPlatformOptions`. Pass the options to the parameter for their
platform instead:

```dart
// Before
await plugin.createCalendar(
  name: 'Work',
  platformOptions: CreateCalendarOptionsAndroid(accountName: 'MyApp'),
);
await plugin.createCalendar(
  name: 'Work',
  platformOptions: CreateCalendarOptionsIos(sourceId: source.id),
);

// After
await plugin.createCalendar(
  name: 'Work',
  android: CalendarOptionsAndroid(accountName: 'MyApp'),
);
await plugin.createCalendar(
  name: 'Work',
  ios: CalendarOptionsIos(sourceId: source.id),
);
```

`CreateCalendarOptionsAndroid` is now `CalendarOptionsAndroid`, and
`CreateCalendarOptionsIos` is now `CalendarOptionsIos`. Their fields are the
same, but they're optional now, so you can pass both in one call.
