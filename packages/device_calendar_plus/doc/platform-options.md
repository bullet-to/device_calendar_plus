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

## Attendees (Android)

Android's Calendar Provider lets an app write an event's guest list (the
`CalendarContract.Attendees` rows). EventKit can't: `EKEvent.attendees` is
read-only, so on iOS attendees stay read-only. Reading is unchanged on both
platforms, through the shared `Event.attendees`.

Each `AttendeeWriteAndroid` is one Attendees row, with Android's own columns and
value sets: `email` (required), `name`, `type` (`AttendeeTypeAndroid`, the
`ATTENDEE_TYPE` column), `relationship` (`AttendeeRelationshipAndroid`,
`ATTENDEE_RELATIONSHIP`) and `status` (`AttendeeStatusAndroid`,
`ATTENDEE_STATUS`). They're not the shared `AttendeeRole` / `AttendeeStatus`
in disguise. Leave the optional ones out and you get what Android's own
calendar app writes for a guest: `required`, `attendee`, `invited`.

```dart
// Create.
final id = await plugin.createEvent(
  title: 'Planning',
  startDate: start,
  endDate: end,
  android: const EventOptionsAndroid(
    attendees: [
      AttendeeWriteAndroid(email: 'ada@example.com', name: 'Ada'),
      AttendeeWriteAndroid(
        email: 'room-4@example.com',
        type: AttendeeTypeAndroid.resource,
      ),
    ],
  ),
);

// Update: Patch.set replaces the guest list, Patch.clear empties it, and
// leaving it out keeps it.
await plugin.updateEvent(
  instanceId: id,
  android: EventUpdateOptionsAndroid(
    attendees: Patch.set([
      AttendeeWriteAndroid(email: 'ada@example.com', name: 'Ada'),
    ]),
  ),
);
```

Quirks worth knowing:

- **Synced calendars send real invitations.** On a Google or Exchange
  calendar the sync adapter uploads the rows, and the server may email an
  invitation to every address you add (and a cancellation to every one you
  remove). It can also rewrite the rows on the next sync: fill in names,
  change statuses as people respond, or drop an address it can't resolve.
  On a local calendar nobody is contacted. Test against a local calendar
  with addresses you own, or `@example.com` ones.
- **The organizer row stays.** `Event.attendees` skips the organizer row
  (`RELATIONSHIP_ORGANIZER`), and a set or clear leaves it alone, so an event
  keeps its organizer. A set whose list holds an
  `AttendeeRelationshipAndroid.organizer` entry replaces the organizer row
  too, and that entry isn't read back through `Event.attendees`.
- **Blank emails throw.** An attendee whose `email` is empty or whitespace
  throws `ArgumentError` before anything is written, on either platform.
- **Series follow Android's rows**, as status does. `updateRecurring` with
  `EventSpan.allEvents` sets the series' guest list. With
  `EventSpan.thisAndFollowing` the new series gets the original's guest list
  with your edit applied, or the original's as it is when you pass none; on
  a synced calendar that means the new series' guests may be invited to it.
  Occurrences edited on their own keep their own guest list either way.
- **One occurrence.** `updateEvent` on an instance ID sets that occurrence's
  guest list alone. Edit an occurrence without passing attendees and it
  keeps the series' guests.
- **iOS ignores it.** On iOS, `EventOptionsAndroid.attendees` writes nothing,
  and a call whose only change is `android:` is a no-op.

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
