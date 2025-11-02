# device_calendar_plus

A modern, maintained Flutter plugin for reading and writing device calendar events on **Android** and **iOS**.
Modern replacement for the unmaintained [`device_calendar`](https://pub.dev/packages/device_calendar) plugin — rebuilt for 2025 Flutter standards, working towards feature parity with a cleaner API, and no timezone package dependency.

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


## 🛠️ Usage Examples

### Request Permissions

```dart
import 'package:device_calendar_plus/device_calendar_plus.dart';

// Get the singleton instance
final plugin = DeviceCalendar.instance;

// Request calendar permissions
final status = await plugin.requestPermissions();
if (status != CalendarPermissionStatus.granted) {
  // Handle permission denied
  return;
}
```

### List Calendars

```dart
final plugin = DeviceCalendar.instance;

// List all calendars
final calendars = await plugin.listCalendars();
for (final calendar in calendars) {
  print('${calendar.name} (${calendar.readOnly ? "read-only" : "writable"})');
  if (calendar.isPrimary) {
    print('  ⭐ Primary calendar');
  }
  if (calendar.colorHex != null) {
    print('  Color: ${calendar.colorHex}');
  }
}

// Find a writable calendar
final writableCalendar = calendars.firstWhere(
  (cal) => !cal.readOnly,
  orElse: () => calendars.first,
);
```

### Retrieve Events

```dart
final plugin = DeviceCalendar.instance;

// Get events for the next 30 days
final now = DateTime.now();
final startDate = now;
final endDate = now.add(const Duration(days: 30));

// Get events from all calendars
final allEvents = await plugin.retrieveEvents(
  startDate,
  endDate,
);
print('Found ${allEvents.length} events');

// Get events from specific calendars only
final calendarIds = ['calendar-id-1', 'calendar-id-2'];
final filteredEvents = await plugin.retrieveEvents(
  startDate,
  endDate,
  calendarIds: calendarIds,
);

```

### Get Single Event

```dart
final plugin = DeviceCalendar.instance;

// Get a specific event by instanceId
final event = await plugin.getEvent(event.instanceId);
if (event != null) {
  print('Event: ${event.title}');
}

// For recurring events, get a specific occurrence
final instance = await plugin.getEvent(event.instanceId);

// For recurring events, get the master event definition
final masterEvent = await plugin.getEvent(event.eventId);
```

### Show Event in Modal

```dart
final plugin = DeviceCalendar.instance;

// Show a specific event in a modal dialog
await plugin.showEvent(event.instanceId);

// For recurring events, show a specific occurrence
await plugin.showEvent(event.instanceId);

// For recurring events, show the master event
await plugin.showEvent(event.eventId);
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