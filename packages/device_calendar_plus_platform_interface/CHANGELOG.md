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