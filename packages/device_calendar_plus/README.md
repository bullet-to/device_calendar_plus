# device_calendar_plus

A modern, maintained Flutter plugin for reading and writing device calendar events on **Android** and **iOS**.
Modern replacement for the unmaintained [`device_calendar`](https://pub.dev/packages/device_calendar) plugin — rebuilt for 2025 Flutter standards, working towards feature parity with a cleaner API, and no timezone package dependency.

[![pub package](https://img.shields.io/pub/v/device_calendar_plus.svg)](https://pub.dev/packages/device_calendar_plus)
[![pub points](https://img.shields.io/pub/points/device_calendar_plus)](https://pub.dev/packages/device_calendar_plus/score)
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

## 🚀 Features

- **Permissions**: Request and check calendar permissions
- **Calendars**: Create, read, update, and delete calendars
- **Events**: Create, read, update, and delete events
- **Query**: Retrieve events by date range or specific event IDs
- **Native UI**: Open native event modal for viewing/editing in both android and iOS
- **All-Day Events**: Proper handling of floating calendar dates
- **Timezones**: Correct timezone behavior for timed events
- **Recurring Events**: Read recurring event instances; update/delete entire series
- **Attendees**: Add, retrieve, and manage event invitees/attendees

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

**ProGuard / R8**: ProGuard rules are automatically applied by the plugin. No manual configuration needed.

## ⏰ DateTime and Timezone Behavior

**All DateTimes returned by this plugin are in local time.**

### All-Day Events (Floating Dates)

All-day events are treated as **floating calendar dates**, not specific instants in time. This means:

- An all-day event for "January 15, 2024" will always display as January 15, regardless of what timezone your device is in
- The date components (year, month, day) are preserved across timezone changes
- **Do NOT convert all-day event DateTimes to UTC** — they represent calendar dates, not moments in time
- Example: A birthday on "January 15" should always show as January 15, whether you're in New York or Tokyo

### Non-All-Day Events (Instants in Time)

Regular timed events represent specific moments in time and can be converted to UTC as needed:

- These events have specific start/end times in a timezone (e.g., "3:00 PM New York time")
- They represent absolute instants that correspond to different local times across timezones
- **You can freely convert these DateTimes to UTC** for storage, comparison, or API calls
- Example: A meeting at "3:00 PM EST" is the same instant as "12:00 PM PST"

### Summary

```dart
// All-day event - treat as a calendar date, NOT a UTC instant
final birthdayEvent = await plugin.getEvent(birthdayId);
if (birthdayEvent.isAllDay) {
  // ✅ Use the date components directly
  print('Birthday: ${birthdayEvent.startDate.year}-${birthdayEvent.startDate.month}-${birthdayEvent.startDate.day}');

  // ❌ Don't convert to UTC - it's a calendar date, not a moment in time
  // final utcDate = birthdayEvent.startDate.toUtc(); // DON'T DO THIS
}

// Regular timed event - this IS an instant in time
final meetingEvent = await plugin.getEvent(meetingId);
if (!meetingEvent.isAllDay) {
  // ✅ Convert to UTC for storage/comparison
  final utcTime = meetingEvent.startDate.toUtc();

  // ✅ Format in local time for display
  print('Meeting at: ${meetingEvent.startDate}');
}
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

> **Note on error codes:** > `DeviceCalendarError` exists for developer ergonomics and clearer `switch` handling.
> We may introduce new enum values in future minor versions as new error cases appear.
> We do not consider this a breaking change.

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

### Check Permissions

Use `hasPermissions()` to check the current permission status without prompting the user:

```dart
final plugin = DeviceCalendar.instance;

// Check current permission status (doesn't prompt)
final status = await plugin.hasPermissions();

if (status == CalendarPermissionStatus.granted) {
  // Permissions already granted
  final calendars = await plugin.listCalendars();
} else if (status == CalendarPermissionStatus.notDetermined) {
  // User hasn't been asked yet - now we can prompt
  final newStatus = await plugin.requestPermissions();
} else {
  // Denied or restricted - show appropriate UI
  print('Permissions: $status');
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
final allEvents = await plugin.listEvents(
  startDate,
  endDate,
);
print('Found ${allEvents.length} events');

// Get events from specific calendars only
final calendarIds = ['calendar-id-1', 'calendar-id-2'];
final filteredEvents = await plugin.listEvents(
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
await plugin.showEventModal(event.instanceId);

// For recurring events, show a specific occurrence
await plugin.showEventModal(event.instanceId);

// For recurring events, show the master event
await plugin.showEventModal(event.eventId);
```

### Create Event

```dart
final plugin = DeviceCalendar.instance;

// Create a basic event
final eventId = await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Team Meeting',
  startDate: DateTime(2024, 3, 20, 14, 0),
  endDate: DateTime(2024, 3, 20, 15, 0),
);

// Create an all-day event
final allDayEventId = await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Conference',
  startDate: DateTime(2024, 3, 20),
  endDate: DateTime(2024, 3, 21),
  isAllDay: true,
);

// Create event with all optional parameters
final detailedEventId = await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Project Kickoff',
  startDate: DateTime(2024, 3, 20, 10, 0),
  endDate: DateTime(2024, 3, 20, 12, 0),
  description: 'Quarterly project kickoff meeting',
  location: 'Conference Room A',
  timeZone: 'America/New_York',
  availability: EventAvailability.busy,
);
```

### Create Recurring Event

You can create recurring events by passing a `RecurrenceRule` object:

```dart
// Create a daily recurring event (repeats forever)
await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Daily Standup',
  startDate: DateTime(2024, 3, 20, 9, 0),
  endDate: DateTime(2024, 3, 20, 9, 15),
  recurrenceRule: RecurrenceRule(
    frequency: RecurrenceFrequency.daily,
  ),
);

// Create a weekly event that ends after 10 occurrences
await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Weekly Sync',
  startDate: DateTime(2024, 3, 20, 10, 0),
  endDate: DateTime(2024, 3, 20, 11, 0),
  recurrenceRule: RecurrenceRule(
    frequency: RecurrenceFrequency.weekly,
    interval: 1,
    occurrences: 10,
    daysOfWeek: [DayOfWeek.monday, DayOfWeek.wednesday], // repeats on Mon & Wed
  ),
);

// Create a monthly event that ends on a specific date
await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Monthly Review',
  startDate: DateTime(2024, 3, 1, 14, 0),
  endDate: DateTime(2024, 3, 1, 15, 0),
  recurrenceRule: RecurrenceRule(
    frequency: RecurrenceFrequency.monthly,
    endDate: DateTime(2024, 12, 31),
  ),
);
```

### Create Event with Attendees

You can add attendees/invitees when creating an event:

```dart
final plugin = DeviceCalendar.instance;

// Create an event with attendees
final eventId = await plugin.createEvent(
  calendarId: 'your-calendar-id',
  title: 'Team Meeting',
  startDate: DateTime(2024, 3, 20, 14, 0),
  endDate: DateTime(2024, 3, 20, 15, 0),
  attendees: [
    Attendee(
      name: 'John Doe',
      emailAddress: 'john.doe@example.com',
      role: AttendeeRole.required,
      status: AttendeeStatus.invited,
    ),
    Attendee(
      name: 'Jane Smith',
      emailAddress: 'jane.smith@example.com',
      role: AttendeeRole.optional,
    ),
  ],
);
```

> [!IMPORTANT] > **iOS Limitation**: Programmatically adding invitees/attendees to an event is **not supported** implementation-wise by Apple's EventKit framework (the `attendees` property is read-only). On iOS, you can only _retrieve_ existing attendees from events. To add attendees on iOS, you must use the native `EKEventEditViewController` UI or Apple's Calendar app. The `attendees` parameter will be ignored on iOS during creation and updates.

### Retrieve Event Attendees

Attendees are automatically included when retrieving events:

```dart
final plugin = DeviceCalendar.instance;

// Get an event
final event = await plugin.getEvent(eventId);

// Check if the event has attendees
if (event?.attendees != null && event!.attendees!.isNotEmpty) {
  for (final attendee in event.attendees!) {
    print('${attendee.name ?? attendee.emailAddress}');
    print('  Role: ${attendee.role}');       // required, optional, resource, none
    print('  Status: ${attendee.status}');   // invited, accepted, declined, tentative, none
    print('  Organizer: ${attendee.isOrganizer}');
    print('  Current User: ${attendee.isCurrentUser}');
  }
}
```

### Attendee Model

The `Attendee` class includes:

| Property        | Type             | Description                                               |
| --------------- | ---------------- | --------------------------------------------------------- |
| `name`          | `String?`        | Display name of the attendee                              |
| `emailAddress`  | `String?`        | Email address (primary identifier)                        |
| `role`          | `AttendeeRole`   | `required`, `optional`, `resource`, or `none`             |
| `status`        | `AttendeeStatus` | `invited`, `accepted`, `declined`, `tentative`, or `none` |
| `isOrganizer`   | `bool`           | Whether this attendee is the event organizer              |
| `isCurrentUser` | `bool`           | Whether this attendee is the current device user          |

### Update Event

```dart
final plugin = DeviceCalendar.instance;

// Update event title
await plugin.updateEvent(
  instanceId: event.instanceId,
  title: 'Updated Meeting Title',
);

// Update multiple fields
await plugin.updateEvent(
  instanceId: event.instanceId,
  title: 'Team Sync',
  startDate: DateTime(2024, 3, 21, 15, 0),
  endDate: DateTime(2024, 3, 21, 16, 0),
  location: 'Conference Room B',
  description: 'Updated description',
);

// Change a timed event to all-day
await plugin.updateEvent(
  instanceId: event.instanceId,
  isAllDay: true,
);

// Change an all-day event to timed
await plugin.updateEvent(
  instanceId: event.instanceId,
  isAllDay: false,
  startDate: DateTime(2024, 3, 21, 10, 0),
  endDate: DateTime(2024, 3, 21, 11, 0),
);

// Update timezone (reinterprets local time)
// Note: "3 PM EST" becomes "3 PM PST" (different instant in time)
await plugin.updateEvent(
  instanceId: event.instanceId,
  timeZone: 'America/Los_Angeles',
);
```

**Note on Recurring Events**: For recurring events, `updateEvent` will always update the ENTIRE series (all past and future occurrences). Single-instance updates are not supported to maintain consistent behavior across platforms.

### UI Event Editor

For situations where programmatic event creation is limited (e.g. adding attendees on iOS), you can launch the native calendar editor UI.

**Important**:

- **iOS**: Returns the `eventId` if the user saves the event, or `null` if cancelled. **Note**: Pre-filling `attendees` is NOT supported on iOS; the `attendees` list will be ignored.
- **Android**: Always returns `null` as the native intent system does not return the created event ID. Supports pre-filling all fields including `attendees`.

```dart
final plugin = DeviceCalendar.instance;

// Create a new event with optional pre-filled data
await plugin.createOrEditEventModal(
  eventData: Event(
    '1', // calendar ID
    title: 'New Meeting',
    start: DateTime.now(),
    end: DateTime.now().add(Duration(hours: 1)),
    attendees: [
      Attendee(
        emailAddress: 'colleague@example.com',
        role: AttendeeRole.required,
      ),
    ],
  ),
);

// Edit an existing event
await plugin.createOrEditEventModal(
  eventId: 'existing_event_id',
);
```

### Delete Event

```dart
final plugin = DeviceCalendar.instance;

// Delete a single event
await plugin.deleteEvent(event.instanceId);

// For recurring events, this deletes the ENTIRE series (all occurrences)
await plugin.deleteEvent(event.instanceId);
```

## 🤝 Contributing

Contributions, PRs and issue reports welcome.
Open an issue first for larger features or breaking changes.

- Code style: `dart format .`
- Run tests: `flutter test`
- Federated layout: platform code lives in
  `/packages/device_calendar_plus_android` and `/packages/device_calendar_plus_ios`;
  shared contracts in `/packages/device_calendar_plus_platform_interface`.

## 🧪 Testing Status

This plugin includes both **unit tests** and **integration tests** to ensure reliability.

## 📄 License

MIT © 2025 Bullet
See [LICENSE](LICENSE) for details.

---

**Maintained by [Bullet](https://bullet.to)** — a cross-platform task + notes + calendar app built with Flutter.
