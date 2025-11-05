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