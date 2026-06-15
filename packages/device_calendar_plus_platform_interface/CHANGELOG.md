## 0.5.2 - 2026-06-15

- No functional changes; version aligned with the rest of the suite for the
  0.5.2 release

## 0.5.1 - 2026-06-15

### Docs
- Clarified `showEventModal` docs: the `edit` flag only sets the modal's
  starting mode; the native view screen still lets the user edit on both
  platforms

## 0.5.0 - 2026-06-11

### Changed
- **Breaking:** `updateRecurring()` reworked — positional `eventId`, occurrence
  `timestamp` and `span`, with `startTime` (`EventTimeOfDay`) and
  `durationMinutes` replacing absolute dates, and `recurrenceRule` taking a
  `Patch<String>` (RRULE); returns the affected scope's event ID
- **Breaking:** `updateEvent()` and `deleteEvent()` take an optional occurrence
  `timestamp`; when set, the operation acts on that single occurrence
- **Breaking:** `span` accepts only `allEvents` and `thisAndFollowing`;
  `thisInstance` is gone

### Added
- `EventTimeOfDay` — validating hour/minute value class

## 0.4.0 - 2026-05-25

### Added
- `updateRecurring()` method with `EventSpan` enum (allEvents / thisAndFollowing / thisInstance)
- `deleteRecurring()` method taking an `EventSpan`
- `url` parameter on `updateEvent()`
- `edit` parameter on `showEventModal()`
- `Patch<T>` sealed type (`Patch.set` / `Patch.clear`) for clearable optional fields

### Changed
- **Breaking:** `updateEvent()` `description`, `location`, and `url` now take `Patch<String>` instead of `String?`

## 0.3.5 - 2026-04-20

Version sync with other packages. No functional changes.

## 0.3.4 - 2026-02-08

Version sync with other packages. No functional changes.

## 0.3.3 - 2025-12-21

Version sync with other packages. No functional changes.

## 0.3.2 - 2025-12-19

### Added
- `CreateCalendarPlatformOptions` base class for platform-specific calendar creation options
- `createCalendar()` now accepts optional `platformOptions` parameter

## 0.3.1 - 2025-11-07

Version sync with other packages. No functional changes.

## 0.3.0 - 2024-11-05

### Changed
- **BREAKING**: `deleteEvent()` signature changed - removed `deleteAllInstances` parameter, operations on recurring events now always delete entire series
- **BREAKING**: `updateEvent()` signature changed - removed `updateAllInstances` parameter, operations on recurring events now always update entire series

### Removed
- **BREAKING**: `NOT_SUPPORTED` platform exception code (no longer needed)

## 0.2.0 - 2024-11-05

### Added
- `openAppSettings()` method to direct users to app settings for permission management

### Removed
- **BREAKING**: `getPlatformVersion()` method (unused boilerplate)

## 0.1.1 - 2024-11-04

Version sync with other packages. No functional changes.

## 0.1.0 - 2024-11-04

Initial release.