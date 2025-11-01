# device_calendar_plus

A modern, maintained Flutter plugin for reading and writing device calendar events on **Android** and **iOS**.
Modern replacement for the unmaintained [`device_calendar`](https://pub.dev/packages/device_calendar) plugin — rebuilt for 2025 Flutter standards, working towards feature parity with a cleaner API.

[![pub package](https://img.shields.io/pub/v/device_calendar_plus.svg)](https://pub.dev/packages/device_calendar_plus)
[![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios-blue.svg)](#)
[![MIT license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## ✨ Overview

`device_calendar_plus` lets Flutter apps read and write native calendar data using:

- **Android** Calendar Provider
- **iOS** EventKit

It provides a **clean Dart API**, proper **time-zone handling**, and an **actively maintained** federated structure.

Created by [Bullet](https://bullet.to) — a personal task + notes + calendar app using this plugin in production.

## ✅ Supported versions

| Platform    | Min OS / SDK   | Target / Compile       |
| ----------- | -------------- | ---------------------- |
| **Android** | **minSdk 24+** | **target/compile 35**  |
| **iOS**     | **iOS 13+**    | Latest Xcode / iOS SDK |

## 🚀 Features (v0.1.0)

- Request and check permissions
- List device calendars (read-only or writable)
- Query events by date range or specific IDs
- Open native event modal
- Correct all-day and time-zone behaviour
- Federated plugin structure ready for community PRs

## 🧩 Installation

Add the dependency to your project:

```yaml
dependencies:
  device_calendar_plus: <latest version>
```



### iOS

Add usage descriptions to your app’s **Info.plist**:

```xml
<!-- iOS 10–16 (legacy key, still valid) -->
<key>NSCalendarsUsageDescription</key>
<string>Access your calendar to view and manage events.</string>

<!-- iOS 17+ (choose as appropriate) -->
<key>NSCalendarsFullAccessUsageDescription</key>
<string>Full access to view and edit your calendar events.</string>
<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>Add events without reading existing events.</string>
```

### Android

Add calendar permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_CALENDAR" />
<uses-permission android:name="android.permission.WRITE_CALENDAR" />
```


## 🛠️ Example

```dart
final calendar = DeviceCalendar.instance;

// Ask for permission
final granted = await calendar.requestPermissions();
if (!granted) return;

// List calendars
final calendars = await calendar.listCalendars();

// Query events
final events = await calendar.getEvents(
  calendarId: calendars.first.id,
  start: DateTime.now().subtract(const Duration(days: 7)),
  end: DateTime.now().add(const Duration(days: 7)),
);

await calendar.showEventModal(events.first.eventId);
```

## 🧱 Exception model

Each `DeviceCalendarException` uses an enum code to describe the error type:

```dart
enum DeviceCalendarError {
  permissionDenied,
  ...
}
```

This enum provides stable, descriptive error codes for all exceptions thrown by the plugin.

> **Note on error codes:**
> `DeviceCalendarError` exists for developer ergonomics and clearer `switch` handling.
> We may introduce new enum values in future minor versions as new error cases appear.
We do not consider this a breaking change.

## 🤝 Contributing

Contributions, PRs and issue reports welcome.
Open an issue first for larger features or breaking changes.

- Code style: `dart format .`
- Run tests: `flutter test`
- Federated layout: platform code lives in
  `/packages/device_calendar_plus_android` and `/packages/device_calendar_plus_ios`;
  shared contracts in `/packages/device_calendar_plus_platform_interface`.

## 📄 License

MIT © 2025 Bullet
See [LICENSE](LICENSE) for details.

> Maintained by [Bullet](https://bullet.to) — a cross-platform task + notes + calendar app built with Flutter.