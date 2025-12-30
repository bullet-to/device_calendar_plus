## 0.3.4 - 2025-12-30

- Added support for recurring events

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
