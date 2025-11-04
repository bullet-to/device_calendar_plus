## 0.1.0

Initial release of device_calendar_plus - a modern, maintained Flutter plugin for calendar access.

### Features

- **Permissions Management**: Request and check calendar permissions on Android and iOS
- **Calendar Management**: List device calendars with metadata (name, color, read-only status, primary flag)
- **Event Querying**: Retrieve events by date range with optional calendar filtering
- **Single Event Retrieval**: Get specific events by ID with support for recurring event instances
- **Show Event Modal**: Open native event detail view
- **Event Creation**: Create events with full metadata support (title, description, location, time zone, availability)
- **Event Updates**: Update existing events including all-day toggle and timezone changes
- **Event Deletion**: Delete single events or all instances of recurring events
- **All-Day Event Support**: Proper handling of floating calendar dates vs. timed events
- **Timezone Handling**: Correct timezone behavior for both all-day and timed events
- **Exception Model**: Typed error codes with `DeviceCalendarException` and `DeviceCalendarError` enum
- **Federated Architecture**: Clean separation between platform interface and implementations

### Platform Support

- Android (API 24+, target/compile 35)
- iOS 13+

### Known Limitations

- iOS 17+ write-only permissions are detected but events cannot be modified in write-only mode (matches platform limitations)
- Recurring event creation not yet supported (coming in future release)
- Recurring event updates apply to all instances (no single-instance editing yet)
