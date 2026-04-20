## 0.3.5 - 2026-04-20

### Fixed
- Calendar source lookup fallback when default source is unavailable (#13)
- `createCalendar` default fallback prefers iCloud over other CalDAV sources (#33)

## 0.3.4 - 2026-02-08

### Added
- Swift Package Manager support (CocoaPods continues to work as before)

## 0.3.3 - 2025-12-21

### Fixed
- Fixed parsing of `instanceId` for events with `@` in their event ID (e.g., Google Calendar IDs like `abc123@google.com`)

## 0.3.2 - 2025-12-19

### Changed
- `createCalendar()` signature updated to accept optional `platformOptions` parameter (ignored on iOS)

## 0.3.1 - 2025-11-07

### Fixed
- `showEvent()` now properly stores result callback and calls it in `eventViewController(_:didCompleteWith:)` delegate method after modal is dismissed

## 0.3.0 - 2024-11-05

### Changed
- **BREAKING**: `deleteEvent()` now always deletes entire series for recurring events using `EKSpan.futureEvents` on master event (removed `deleteAllInstances` parameter)
- **BREAKING**: `updateEvent()` now always updates entire series for recurring events using `EKSpan.futureEvents` on master event (removed `updateAllInstances` parameter)
- Native code now extracts event ID from instance ID format automatically and fetches master event

### Removed
- **BREAKING**: `NOT_SUPPORTED` error code (no longer needed)

## 0.2.0 - 2024-11-05

### Added
- `openAppSettings()` implementation using UIApplication.openSettingsURLString

### Removed
- **BREAKING**: `getPlatformVersion()` implementation (unused boilerplate)

## 0.1.1 - 2024-11-04

Version sync with other packages. No functional changes.

## 0.1.0 - 2024-11-04

Initial release.