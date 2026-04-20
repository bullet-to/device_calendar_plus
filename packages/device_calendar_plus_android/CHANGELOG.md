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