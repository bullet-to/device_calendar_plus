# device_calendar_plus

A Flutter plugin for reading and writing calendar events on **Android** and **iOS**.

The original [`device_calendar`](https://pub.dev/packages/device_calendar) plugin got abandoned, and I needed calendars that actually worked for [Bullet](https://bullet.to). So I rebuilt it: a cleaner Dart API, timezones that behave, and no `timezone` package tagging along. Getting EventKit and Android's Calendar Provider to agree on anything is a proper slog, but that's my problem to lose sleep over, not yours. You just get the tidy bit. 😎

[![pub package](https://img.shields.io/pub/v/device_calendar_plus.svg)](https://pub.dev/packages/device_calendar_plus)
[![pub points](https://img.shields.io/pub/points/device_calendar_plus)](https://pub.dev/packages/device_calendar_plus/score)
[![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios-blue.svg)](#)
[![MIT license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Built for [Bullet](https://bullet.to), a calmer task + notes + calendar app, and running in production there.

## What it does

- **Permissions** - request and check access, including a write-only tier
- **Calendars & sources** - create, read, update, delete, and target a specific account
- **Events** - create, read, update, delete, and query by date range
- **Recurring events** - full RRULE support with a typed `RecurrenceRule` model; edit or delete a whole series, this-and-following, or a single occurrence
- **Reminders** - relative before-start alarms, read and write
- **Native UI** - open the OS event viewer/editor, or a pre-filled create screen
- **All-day & timezones** - floating dates and sane local-time behaviour

## One API, both platforms

I only put things in this plugin that work the same on Android and iOS. If a feature is read-only on one platform, it's read-only here. If it doesn't exist on one, it doesn't go in. Where the two platforms naturally disagree, Android is bent to match iOS, which sets the contract.

It's honest best-effort, though. A few platform realities I just can't paper over: older iOS has no write-only permission tier, and the native editor screens do their own thing across different calendar apps. I call those out in the docs where they show up, rather than hide them behind an API pretending everything's identical.

## Supported versions

| Platform    | Min OS / SDK   | Target / Compile       |
| ----------- | -------------- | ---------------------- |
| **Android** | **minSdk 24+** | **target/compile 35**  |
| **iOS**     | **iOS 13+**    | Latest Xcode / iOS SDK |

## Install

```yaml
dependencies:
  device_calendar_plus: <latest version>
```

### iOS

Add usage descriptions to your app's **Info.plist**:

```xml
<!-- iOS 10-16 (legacy key, still valid) -->
<key>NSCalendarsUsageDescription</key>
<string>Access your calendar to view and manage events.</string>

<!-- iOS 17+ -->
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

ProGuard / R8 rules are applied automatically, so there's nothing to configure.

## Getting started

```dart
import 'package:device_calendar_plus/device_calendar_plus.dart';

final plugin = DeviceCalendar.instance;

// 1. Permissions - either ask for them yourself...
final status = await plugin.requestPermissions();
if (status != CalendarPermissionStatus.granted) return;

//    ...or let methods prompt on first use (set once at app start, then skip
//    the explicit request above):
// plugin.autoPermissions = AutoPermissionMode.full;

// 2. Create an event (omit calendarId to use the default calendar).
final eventId = await plugin.createEvent(
  title: 'Team Meeting',
  startDate: DateTime.now().add(const Duration(hours: 1)),
  endDate: DateTime.now().add(const Duration(hours: 2)),
);

// 3. Read events back.
final now = DateTime.now();
final events = await plugin.listEvents(now, now.add(const Duration(days: 7)));
```

## Permissions

Every read or write needs calendar permission. Ask for it yourself:

```dart
final status = await plugin.requestPermissions();
if (status != CalendarPermissionStatus.granted) return;
```

Add-only apps can ask for the gentler write-only tier (`requestPermissions(level: CalendarAccessLevel.writeOnly)`). Or let methods prompt on first use by setting `autoPermissions` once at app start. Most apps read, so `.full` is the one you usually want:

```dart
DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
```

See [Permissions](doc/permissions.md) for write-only, the automatic modes, and upgrading tiers in-app.

## Dates & timezones

Every `DateTime` the plugin hands back is in **local time**, and there are two kinds (no `timezone` package required):

- **Timed events are instants.** A meeting at "3 PM EST" is a specific moment, so convert `startDate`/`endDate` to UTC freely for storage or comparison. Setting `timeZone` reinterprets the wall-clock time ("3 PM EST" becomes "3 PM PST"), not the instant.
- **All-day events are floating dates.** A birthday on January 15 stays January 15 in any timezone, so use the date components and don't convert to UTC.

## Error handling

Two kinds of errors:

- **`DeviceCalendarException`** - runtime conditions to handle (permission denied, not found, read-only). It carries a `DeviceCalendarError` code to switch on.
- **Standard Dart errors** (e.g. `ArgumentError`, `StateError`) - programmer mistakes caught before any platform call, like invalid arguments. Fix them, don't catch them. A call with nothing to change (e.g. `updateEvent` with no fields) is a harmless no-op, not an error.

```dart
try {
  await plugin.createEvent(/* ... */);
} on DeviceCalendarException catch (e) {
  if (e.errorCode == DeviceCalendarError.permissionDenied) {
    // Ask the user to grant access.
  }
}
```

## More docs

- [Permissions](doc/permissions.md) - request, check, write-only, automatic
- [Calendars & sources](doc/calendars.md) - list, create, update, delete
- [Events](doc/events.md) - create, list, get, update, delete
- [Recurring events](doc/recurring-events.md) - rules, series edits, occurrences
- [Reminders](doc/reminders.md) - relative before-start alarms
- [Native UI](doc/native-ui.md) - view, edit, and create modals

## Contributing

I'm keeping pull requests closed, and not to be precious about it. Holding the whole API and the iOS/Android parity in my own head is honestly the only way I keep it consistent. Bug reports and feature requests are very welcome though, so open an issue and let's chat. :)

## License

MIT © 2025 Bullet. See [LICENSE](LICENSE).

---

Made by [Bullet](https://bullet.to), a task + notes + calendar app built with Flutter.
