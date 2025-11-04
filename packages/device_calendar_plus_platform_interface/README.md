# device_calendar_plus_platform_interface

Platform interface for the `device_calendar_plus` plugin.

This package defines the interface that platform implementations must implement. It is not intended to be used directly by application developers.

## For App Developers

If you're building a Flutter app, use the main [`device_calendar_plus`](https://pub.dev/packages/device_calendar_plus) package instead.

## For Plugin Developers

This package contains:
- Method channel constants and method names
- Platform interface abstract class
- Data serialization contracts for calendars and events
- Permission status and error code definitions

Platform implementations:
- [`device_calendar_plus_android`](https://pub.dev/packages/device_calendar_plus_android) - Android implementation
- [`device_calendar_plus_ios`](https://pub.dev/packages/device_calendar_plus_ios) - iOS implementation

## License

MIT © 2025 Bullet
