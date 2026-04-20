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