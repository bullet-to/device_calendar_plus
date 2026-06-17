## Unreleased

### Changed
- **Breaking:** `WeeklyRecurrence`'s `wkst` field and constructor parameter are
  renamed to `weekStart`, matching the spelled-out naming of the other
  recurrence fields (`daysOfWeek`, `daysOfMonth`, `setPositions`, …). The
  emitted RRULE is unchanged (still uses the `WKST=` token). Update
  `WeeklyRecurrence(wkst: …)` call sites and `.wkst` reads to `weekStart`.

## 0.7.1 - 2026-06-17

### Changed
- Add the `device` pub.dev topic (dropped `federated` to stay within the
  five-topic limit).

### Docs
- Slimmed the README to an overview plus a getting-started snippet, and moved
  the worked examples into focused topic guides under `doc/`. Trimmed the API
  doc comments to the consumer-facing contract and removed native-API
  implementation details. No code or behavior changes.

## 0.7.0 - 2026-06-17

### Added
- Write-only calendar access. `requestPermissions(level:
  CalendarAccessLevel.writeOnly)` asks for the gentler add-only prompt and a
  grant reports `CalendarPermissionStatus.writeOnly`. On iOS this is not a
  permanent ceiling — a later full request re-prompts and upgrades the app
  in-app (#89).
- Automatic permission handling. Set `DeviceCalendar.instance.autoPermissions`
  to `AutoPermissionMode.asNeeded` or `.full` and methods request the access
  they need on first use instead of throwing when permission is undetermined
  (#90).
- `createEvent`'s `calendarId` is now optional — omit it to write to the
  platform's default calendar (iOS `defaultCalendarForNewEvents`, Android the
  primary or first writable calendar). Resolving the default on Android reads
  the calendar list, so that path needs full access (#88).
- Event reminders. `createEvent` takes `reminders: List<Duration>`,
  `updateEvent` takes `Patch<List<Duration>>`, and `Event.reminders` is read
  back. Relative before-start offsets, normalized to whole minutes on both
  platforms (#87).

## 0.6.0 - 2026-06-16

### Changed
- **Breaking:** `updateRecurring()` now takes `start: DateTime` instead of
  `startTime: EventTimeOfDay`. `start` is the anchored occurrence's new start;
  the whole scope translates by the wall-clock delta, so a single call can move
  the **time and the day together** — a nightshift 11 PM → 1 AM (crosses
  midnight) or a weekly meeting Monday → Tuesday. The delta is measured in the
  event's timezone, so it is DST-safe. (#103, thanks @SuperKrallan)
- **Breaking:** `EventTimeOfDay` is removed.
- **Breaking:** all-day events now accept `start` (only its date is used)
  instead of throwing.

### Added
- `updateRecurring()` translates implicit-day rules for free: a
  `WeeklyRecurrence()` / `MonthlyRecurrence()` with no pinned day follows the
  anchor when you move the day.

### Behaviour
- Moving the day of a rule that **pins** it explicitly (`daysOfWeek`,
  `daysOfMonth`, positional) without also passing a `recurrenceRule` throws
  `DeviceCalendarException(invalidArguments)`. Moving one day of a multi-day
  rule is genuinely ambiguous (Mon of Mon/Wed/Fri → Tue could mean Tue/Wed/Fri
  or Tue/Thu/Sat), so the API hands the decision back to you. Time-only,
  duration-only and whole-week shifts never throw.

## 0.5.2 - 2026-06-15

### Changed
- No-op updates are now valid instead of throwing. `updateEvent`,
  `updateRecurring` and `updateCalendar` return without a platform write when
  no fields are provided, so "save with no edits" is a harmless no-op rather
  than an `ArgumentError` (#95). `updateRecurring` returns the targeted scope's
  event id. `updateRecurring`'s `duration` now accepts zero (an instantaneous
  event); only a negative duration is rejected.

### Fixed
- Recurrence parsing accepts a negative `BYMONTHDAY` (e.g. `-1` for the last
  day of the month) instead of rejecting the rule (#91)
- Turning a recurring occurrence non-recurring with `thisAndFollowing` +
  `Patch.clear()` now splits the series on iOS instead of collapsing the whole
  series into one event (#93) — see the `device_calendar_plus_ios` changelog
- `listEvents` returns every event across spans longer than ~4 years without
  dropping or duplicating recurring instances (iOS, #94), and includes
  zero-duration events sitting exactly on the query start (Android, #416) — see
  the platform changelogs
- `createCalendar` fails with a clear error on iOS sources that can't hold
  calendars, instead of an opaque failure (#96) — see the
  `device_calendar_plus_ios` changelog
- iOS EventKit operations run off the main thread, preventing UI stalls on
  large calendars (#79) — see the `device_calendar_plus_ios` changelog

### Docs
- Documented `listEvents` per-instance expansion and the `eventId@timestamp`
  instanceId format (#97)

## 0.5.1 - 2026-06-15

### Fixed
- iOS: `showEventModal(edit: true)` no longer crashes (#77) — see the
  `device_calendar_plus_ios` 0.5.1 changelog

### Docs
- Clarified `showEventModal` docs: the view modal (`edit: false`) is **not**
  read-only — on both iOS and Android the native screen lets the user edit the
  event, and those edits are saved directly by the OS

## 0.5.0 - 2026-06-11

### Changed
- **Breaking:** `updateRecurring()` is redesigned around series semantics (#69).
  Times are now expressed as `startTime` (`EventTimeOfDay`) plus `duration`
  instead of absolute `startDate`/`endDate`, so every occurrence keeps its own
  date — changing a series' time no longer re-anchors the series to the
  occurrence you happened to edit (#68, thanks @SuperKrallan). The recurrence
  rule is now a `Patch<RecurrenceRule>`: `Patch.set` replaces it, `Patch.clear`
  collapses the series into a single event. Returns the event ID of the
  affected scope.
- **Breaking:** `EventSpan.thisInstance` is gone — `EventSpan` is now just
  `allEvents` and `thisAndFollowing`. Single occurrences are handled by
  `updateEvent` / `deleteEvent` with an instance ID (below).
- **Breaking:** `updateEvent()` with an instance ID (`eventId@timestamp`)
  edits only that occurrence, detaching it from the series; a bare event ID
  on a recurring event updates the whole series.
- **Breaking:** `deleteEvent()` with an instance ID removes only that
  occurrence; a bare event ID deletes the event (the whole series when
  recurring).

### Added
- `EventTimeOfDay` — small validating hour/minute value class used by
  `updateRecurring()`.

### Fixed
- Occurrence edits with a `startDate` past the occurrence's untouched end
  are rejected with `invalidArguments` on iOS too, matching Android, instead
  of saving an inverted event.
- Android: events with no status read back as `EventStatus.none` instead of
  `EventStatus.tentative` — thanks @mauriziopinotti (#70).
- Android: all Calendar Provider work runs on a background thread; large
  calendars could ANR — thanks @mauriziopinotti (#73).

## 0.4.0 - 2026-05-25

### Added
- `updateRecurring()` — update a recurring event with a span choice:
  `EventSpan.allEvents` (whole series), `thisAndFollowing` (this
  occurrence and every later one), or `thisInstance` (only this occurrence).
  Can change or remove the recurrence rule. Resolves the long-standing
  limitation that `updateEvent()` could not edit recurrence.
  Based on @SuperKrallan (#36)
- `deleteRecurring()` — delete part of a recurring event with a span choice:
  `EventSpan.allEvents` (whole series), `thisAndFollowing` (this occurrence
  and every later one), or `thisInstance` (only this occurrence). Now
  supported on both iOS and Android (Android uses EXDATE on the master
  rather than a cancelled exception event).
  Based on @SuperKrallan (#43)
- `EventSpan` enum for choosing the scope of a recurring-event operation,
  shared by `updateRecurring()` and `deleteRecurring()`
- `url` parameter on `updateEvent()` — based on @SuperKrallan (#38)
- `edit` parameter on `showEventModal()` — when `true`, opens the native editor
  directly (`EKEventEditViewController` on iOS, `ACTION_EDIT` on Android)
  instead of the read-only viewer. Based on @xonaman (#45)
- `Calendar.color` getter — derived Flutter `Color?` parsed from `colorHex`,
  saving consumers from writing the same hex-parsing helper. Based on @xonaman (#46)

### Changed
- **Breaking:** `updateEvent()` `description`, `location` and `url` now take a
  `Patch<String>` instead of a `String`. `null` leaves the field unchanged,
  `Patch.set(value)` assigns a value, `Patch.clear()` removes it — clearing an
  optional field was previously impossible.

### Fixed
- Missing `availability` parameter in platform interface test mock — based on @SuperKrallan (#39)

## 0.3.5 - 2026-04-20

### Added
- `listSources()` to discover calendar accounts/sources — based on @magic-fit (#14)
- Source selection on `createCalendar` — iOS via `CreateCalendarOptionsIos(sourceId:)`, Android via optional `accountType`
- `supportsCalendarCreation` on `CalendarSource`
- `availability` parameter on `updateEvent()` — thanks @SuperKrallan (#29)
- `url` field on events (iOS: `EKEvent.url`, Android: `CUSTOM_APP_URI`) — thanks @magic-fit (#32)
- `showCreateEventModal()` with optional pre-fill (title, dates, location, description)
- Read-only `attendees` on events (name, email, role, status)

### Fixed
- Android: all-day events appearing in wrong day's query in non-UTC timezones (#20)
- Android: `hasPermissions()` now works from background services without an Activity (#31)
- Android: calendar/event queries use application context for background compatibility — thanks @vitalii-vov (#26)
- Android: `notDetermined` permission status correctly distinguished from `denied` — thanks @Albert221 (#12)
- iOS: calendar source lookup fallback when default source is unavailable — thanks @zaqwery (#13)
- iOS: `createCalendar` default fallback now picks iCloud over Gmail CalDAV (#33)

## 0.3.4 - 2026-02-08

### Added
- iOS: Swift Package Manager support

## 0.3.3 - 2025-12-21

### Fixed
- Fixed parsing of `instanceId` for events with `@` in their event ID (e.g., Google Calendar IDs like `abc123@google.com`)

## 0.3.2 - 2025-12-19

### Added
- Android: `CreateCalendarOptionsAndroid` for specifying custom account name when creating calendars
- `createCalendar()` now accepts optional `platformOptions` parameter for platform-specific configuration

## 0.3.1 - 2025-11-07

### Fixed
- `showEventModal()` now properly awaits until the modal is dismissed (iOS and Android)

## 0.3.0 - 2024-11-05

### Changed
- **BREAKING**: `deleteEvent()` now requires named parameter `eventId` and always deletes entire series for recurring events
- **BREAKING**: `updateEvent()` now uses named parameter `eventId` (renamed from `instanceId`) and always updates entire series for recurring events
- **BREAKING**: Removed `deleteAllInstances` and `updateAllInstances` parameters - operations on recurring events now always affect the entire series
- Renamed `getEvent()` and `showEventModal()` parameter from `instanceId` to `id` to clarify that both event IDs and instance IDs are accepted

### Removed
- **BREAKING**: `NOT_SUPPORTED` error code (no longer needed)

## 0.2.0 - 2024-11-05

### Added
- `openAppSettings()` method to guide users to system settings when permissions are denied
- Testing status documentation in README

### Removed
- **BREAKING**: `getPlatformVersion()` method (unused boilerplate)

### Changed
- Updated all platform packages to 0.2.0

## 0.1.1 - 2024-11-04

### Added
- Android: ProGuard/R8 rules for release build compatibility

## 0.1.0 - 2024-11-04

Initial release.

### Added
- Calendar permissions management (request/check)
- List device calendars with metadata (name, color, read-only status, primary flag)
- Query events by date range with optional calendar filtering
- Get single event by ID with support for recurring event instances
- Create events with full metadata support
- Update events including single-instance and all-instance updates for recurring events
- Delete events (single or all instances)
- Show native event modal
- All-day event support with floating date behavior
- Timezone handling for timed events
- Typed exception model with `DeviceCalendarException` and `DeviceCalendarError` enum
- Federated plugin architecture (Android + iOS)
- Support for Android API 24+ (target/compile 35)
- Support for iOS 13+