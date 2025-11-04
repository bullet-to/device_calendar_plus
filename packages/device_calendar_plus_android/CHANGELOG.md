## 0.1.0

Initial release of the Android implementation for device_calendar_plus.

### Features

- Android Calendar Provider integration
- Full calendar and event CRUD operations
- Permissions handling via Android runtime permissions
- Support for Android API 24+ (target/compile 35)
- Proper timezone handling using Android TimeZone API
- All-day event support with floating date behavior
- Event availability/status mapping to Android calendar fields

### Implementation Details

- Written in Kotlin
- Uses Android Calendar Provider ContentResolver API
- Handles permissions via ActivityCompat
- Timezone conversions using java.util.TimeZone and java.time APIs
