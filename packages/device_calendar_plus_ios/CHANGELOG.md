## 0.1.0

Initial release of the iOS implementation for device_calendar_plus.

### Features

- EventKit integration for iOS calendar access
- Full calendar and event CRUD operations
- iOS 13+ support with iOS 17+ write-only permissions detection
- Proper timezone handling using NSTimeZone
- All-day event support with floating date behavior
- Event availability/status mapping to EventKit fields
- Native event modal presentation

### Implementation Details

- Written in Swift
- Uses EventKit and EventKitUI frameworks
- Handles iOS 17+ write-only access permissions
- Timezone conversions using TimeZone and DateComponents
- EKEventEditViewController for native event display
