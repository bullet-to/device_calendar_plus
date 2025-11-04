## 0.1.0

Initial release of the platform interface for device_calendar_plus.

### Features

- Defines the platform interface contract for calendar operations
- Method channel constants and method names
- Permission status constants
- Error code definitions
- Data serialization/deserialization for calendars and events

### API Surface

- `getPlatformVersion()` - Platform identification
- `requestPermissions()` - Permission request flow
- `hasPermissions()` - Permission status check
- `listCalendars()` - Retrieve available calendars
- `listEvents()` - Query events by date range
- `getEvent()` - Retrieve single event
- `createEvent()` - Create new event
- `updateEvent()` - Modify existing event
- `deleteEvent()` - Remove event
- `showEventModal()` - Display native event UI

### Plugin Platform Interface

Implements `PlatformInterface` from `plugin_platform_interface` package for type safety and platform implementation verification.
