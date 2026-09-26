## 0.8.0 - 2026-09-26

### Fixed
- Event times are now written at whole seconds, as on iOS. A sub-second
  start was stored with its milliseconds, and some providers (Samsung,
  Android 11) expand a series' occurrences at whole seconds, so
  `getEvent` on the series and its listed occurrences disagreed by up to a
  second. `createEvent`, `updateEvent` and `updateRecurring` now floor start
  and end to the second, and a series re-anchored by `updateRecurring` drops
  any milliseconds it was stored with (#165).
- `updateRecurring` with `thisAndFollowing` now carries an occurrence that
  was edited on its own, and falls on or after the split, into the new
  series, as iOS does. It keeps its own title, time, reminders and other
  edits, and the new series no longer lists a second copy beside it. When
  the split moves the start, the occurrence's slot moves by the same number
  of days. An occurrence deleted on its own stays deleted if the start stays
  put, and comes back if the start moves, matching iOS. On a synced calendar
  the occurrence is re-created on the new series and the old one is deleted,
  since the server ties it to the old series (#158).
- Deletes and recurring edits on a synced calendar (Google, Exchange, any
  account but local) now reach the server. The plugin wrote them as the
  calendar's own sync adapter, which the provider takes as the server's word:
  the row was changed or removed locally, never marked for upload, and the
  next sync brought the event back — one duplicate per delete-and-sync cycle.
  `deleteEvent`, `deleteRecurring` (whole series, one occurrence, or
  `thisAndFollowing`, including the detached occurrences it sweeps) and
  `updateRecurring` now write as the app they are, so the adapter finds a
  `DELETED`/`DIRTY` row to upload; local calendars, which have no adapter,
  keep the direct deletes (#132, #161).
- `deleteRecurring` with `thisAndFollowing` now removes a detached occurrence
  that falls on or after the split. Truncating the series' rule left an
  occurrence that had been edited on its own behind as an orphan row, which
  came back in `listEvents` once the provider next rebuilt its Instances
  cache; iOS removes it, so Android does too.
- `updateCalendar` and `deleteCalendar` refuse a calendar whose access level
  is below contributor — the same calendars `listCalendars` reports as
  `readOnly` — with `READ_ONLY` before writing, instead of renaming or
  deleting any row they were handed (#126).
- `createCalendar` refuses a non-local `accountType` with `READ_ONLY`, as
  `listSources` already reports, instead of sync-adapter-inserting a phantom
  calendar into another account's namespace (#126).
- `listCalendars` reads a NULL display name as empty instead of handing Dart
  a null it casts (#126).
- `getEvent` resolves the instance ID of an all-day recurring occurrence. The
  lookup went through the all-day date filter with a two-second window, which
  collapses to an empty date range in every timezone, so it always returned
  null; it now matches the Instances row on `EVENT_ID` and `BEGIN` (#122).
- `getEvent` with a bare recurring ID returns the master's real end date.
  A recurring row stores `DURATION` with no `DTEND`, and the end used to fall
  back to the start (#122).
- `listEvents` sorts on the start date it reports, so an all-day event lands
  at its local midnight among timed events in non-UTC zones instead of at its
  stored UTC-midnight instant. Matches iOS (#122).
- Editing or deleting a single occurrence of a recurring event on a local
  calendar no longer makes the rest of the series disappear. The Calendar
  Provider keys a series' exceptions by `_sync_id`, which a local calendar
  never gets, so the exception insert wiped the master's occurrences from its
  Instances cache — the earlier ones for good. A local series is now given a
  `_sync_id` before its first exception is written, and deleting the series
  removes its detached occurrences with it (#153).
- `getEvent`, `updateEvent`, `updateRecurring`, and `deleteEvent` /
  `deleteRecurring` for anything short of the whole series no longer see an
  event that another app has deleted but the provider only tombstoned
  (`DELETED=1`, the fate of any event with a `_sync_id` deleted outside a
  sync adapter, which now includes a local series edited per occurrence).
  Such an event reads as not found instead of accepting edits against a row
  that never shows in `listEvents`. On a local calendar a whole-series delete
  still collects the tombstone.
- `updateRecurring` with a new rule anchors the series on the first day that
  rule generates, as iOS does. Changing a weekly series to another weekday
  left its start on the old day, so the first occurrence was stranded there.
  A rule that generates no occurrence at all is refused with
  `INVALID_ARGUMENTS` and the series is left untouched (#140).
- `listEvents` returns an all-day event when the window is a sub-day slice of
  its date (e.g. 10:00–11:00). The all-day date filter mapped both window
  edges to the same UTC midnight, so the range collapsed to nothing; the end
  edge now rounds up to the next UTC midnight when it isn't on a local
  midnight. Matches iOS.

### Changed
- Migrated to Flutter's built-in Kotlin: the plugin no longer applies the
  Kotlin Gradle Plugin itself, which silences the KGP deprecation warning on
  every `flutter build` and keeps the plugin building once Flutter rejects
  plugins that apply KGP themselves (#133).
- Minimum supported SDK is now Flutter 3.44 / Dart 3.12, as the migration
  requires.

## 0.7.2 - 2026-09-21

### Fixed
- `showCreateEventModal` no longer requires `READ_CALENDAR`. `ACTION_INSERT`
  needs no permission, so the gate only blocked the one path that still works
  after a denial (#121, #141).
- `listCalendars`, `listSources`, `listEvents` and `getEvent` throw
  `permissionDenied` when `READ_CALENDAR` isn't held instead of returning an
  empty result (#121).
- Full-tier operations (calendar mutations, event update/delete, recurring
  update/delete) require `READ_CALENDAR` and `WRITE_CALENDAR`; `WRITE_CALENDAR`
  alone is the write-only tier and could previously mutate calendars that iOS
  rejects. The error message names the tier that's missing (#121).
- `showCreateEventModal` writes `EXTRA_EVENT_ALL_DAY` as a boolean extra, so
  the all-day prefill is honoured (#121).

### Changed
- Permission gates are consolidated in `PermissionGates.kt`; event cursor
  projections go through `EventColumns` presets (#119). No behaviour change.

## 0.7.1 - 2026-07-22

### Added
- Event maps include `colorHex` read from `Events.EVENT_COLOR` when the event
  has a custom color; absent otherwise (#117).

## 0.7.0 - 2026-06-17

### Added
- Write-only access: a `writeOnly` request asks for `WRITE_CALENDAR` only.
  `READ_CALENDAR` and `WRITE_CALENDAR` share the `CALENDAR` group, so a later
  full request escalates to read access with no dialog (#89).
- `createEvent` with no `calendarId` resolves a default calendar — the primary
  writable calendar, falling back to the first writable one (#88).
- Event reminders via `CalendarContract.Reminders` rows and `Events.HAS_ALARM`
  (#87).

### Fixed
- Permanent-denial detection keys off `WRITE_CALENDAR`, and a cancelled
  permission dialog no longer reports `denied` (#108).
- `createEvent` with no `calendarId` reports `permissionDenied` rather than
  "no writable calendar" when it can't read the calendar list to resolve a
  default (#112).

## 0.6.0 - 2026-06-16

### Changed
- **Breaking:** `updateRecurring` takes the anchored occurrence's new start
  (`newStartMillis`) instead of `startMinuteOfDay`. `shiftDate` translates the
  series anchor by the wall-clock delta (calendar-day count + time-of-day) in
  the event's `EVENT_TIMEZONE`, so a move can change the day and time together
  and stays correct across DST (#103).

### Fixed
- A time-only `allEvents` edit now re-writes the unchanged RRULE so the
  CalendarProvider re-expands the Instances cache; without it a moved DTSTART
  could read back as a single occurrence.

### Behaviour
- `updateRecurring` rejects a `start` that moves the day of a series whose
  RRULE pins it (`BYDAY` / `BYMONTHDAY` / `BYMONTH`) unless a new rule is also
  supplied (`dayMoveConflictsWithRule`).

## 0.5.2 - 2026-06-15

### Fixed
- `listEvents` now returns a zero-duration (instantaneous) event that sits
  exactly on the query's start time; the half-open overlap check previously
  excluded it (#416)

## 0.5.1 - 2026-06-15

- No functional changes; version aligned with the rest of the suite for the
  0.5.1 release

## 0.5.0 - 2026-06-11

### Changed
- **Breaking:** recurring-edit split — `updateRecurring` / `deleteRecurring`
  accept only `allEvents` and `thisAndFollowing`; single occurrences go through
  `updateEvent` / `deleteEvent` with an occurrence timestamp (detached
  exception rows; deletes via `STATUS_CANCELED` exceptions)
- `updateRecurring` time changes preserve each occurrence's date, replacing
  only the time-of-day; `thisAndFollowing` truncates the master with `UNTIL`
  to match iOS's `EKSpan.futureEvents` split

### Fixed
- Calendar Provider work now runs on a background thread. Method-channel handlers were doing blocking provider queries on the main thread, which could ANR on large calendars (#73). Thanks @mauriziopinotti for the report and a working proof-of-fix.
- A NULL `STATUS` column reads back as `none`; it was defaulted to `0`, which
  is `STATUS_TENTATIVE`, so status-less events came back tentative (#70) —
  thanks @mauriziopinotti

## 0.4.0 - 2026-05-25

### Added
- `updateRecurring()` — series-level recurring-event edits with `EventSpan` (allEvents / thisAndFollowing / thisInstance). `thisAndFollowing` truncates the master with `UNTIL` and starts a new series; `thisInstance` writes a detached exception event.
- `deleteRecurring()` — `allEvents` deletes the master; `thisAndFollowing` truncates via `UNTIL`; `thisInstance` appends to the master's `EXDATE` column (no separate exception event needed).
- `url` field on events via `Events.CUSTOM_APP_URI`
- `Patch<T>` support in `updateEvent()` — null leaves a field unchanged, `Patch.set` writes, `Patch.clear` writes the empty string to remove
- `edit` flag on `showEvent()` — fires `Intent.ACTION_EDIT` instead of `ACTION_VIEW`

### Fixed
- Event deletion now uses sync-adapter context so EventKit-equivalent listEvents calls stop returning the deleted row immediately

### Changed
- Extracted all-day date-conversion helpers; no behaviour change

## 0.3.5 - 2026-04-20

### Fixed
- All-day events appearing in wrong day's query in non-UTC timezones (#20)
- `PermissionService` accepts `Context` — `hasPermissions()` works without an Activity (#31)

## 0.3.4 - 2026-02-08

Version sync with other packages. No functional changes.

## 0.3.3 - 2025-12-21

### Fixed
- Fixed parsing of `instanceId` for events with `@` in their event ID (e.g., Google Calendar IDs like `abc123@google.com`)

## 0.3.2 - 2025-12-19

### Added
- `CreateCalendarOptionsAndroid` for specifying custom account name when creating calendars
- `createCalendar()` now accepts optional `accountName` parameter via platform options

## 0.3.1 - 2025-11-07

### Fixed
- `showEvent()` now uses `startActivityForResult()` to properly await until the calendar activity is dismissed

## 0.3.0 - 2024-11-05

### Changed
- **BREAKING**: `deleteEvent()` now always deletes entire series for recurring events (removed `deleteAllInstances` parameter)
- **BREAKING**: `updateEvent()` now always updates entire series for recurring events (removed `updateAllInstances` parameter)
- Native code now extracts event ID from instance ID format automatically

### Removed
- **BREAKING**: `NOT_SUPPORTED` error code (no longer needed as single-instance operations are not attempted)

## 0.2.0 - 2024-11-05

### Added
- `openAppSettings()` implementation to open Android app settings via Intent

### Removed
- **BREAKING**: `getPlatformVersion()` implementation (unused boilerplate)

## 0.1.1 - 2024-11-04

### Added
- ProGuard/R8 rules to prevent code stripping in release builds
- Automatic consumer ProGuard rules configuration

## 0.1.0 - 2024-11-04

Initial release.