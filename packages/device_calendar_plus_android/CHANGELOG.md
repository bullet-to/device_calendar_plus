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