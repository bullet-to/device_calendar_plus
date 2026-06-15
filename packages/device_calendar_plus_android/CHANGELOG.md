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