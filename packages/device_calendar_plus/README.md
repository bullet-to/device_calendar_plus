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
- **Sources/accounts**: List calendar sources (iCloud, Google, local, etc.) and target a specific account when creating calendars
- **Events**: Create, read, update, and delete events
- **Query**: Retrieve events by date range or specific event IDs
- **Native UI**: Open native event modal for viewing or editing (`edit: true`) on both Android and iOS
- **All-Day Events**: Proper handling of floating calendar dates
- **Timezones**: Correct timezone behavior for timed events
- **Recurring events**: Create, read, and delete recurring events (daily, weekly, monthly, yearly) with full RRULE support
- **Edit a recurring series**: `updateRecurring()` and `deleteRecurring()` with `EventSpan` — apply changes to the whole series, this-and-following, or just one occurrence

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

## 🧱 Error Handling

The plugin throws two categories of errors:

**Runtime errors** — `DeviceCalendarException` with a `DeviceCalendarError` enum code. These represent conditions your app should handle (permission denied, event not found, calendar read-only, etc.):

```dart
try {
  await plugin.createEvent(...);
} on DeviceCalendarException catch (e) {
  switch (e.errorCode) {
    case DeviceCalendarError.permissionDenied:
      // Ask user to grant permission
    case DeviceCalendarError.notFound:
      // Calendar or event doesn't exist
    default:
      // Handle other cases
  }
}
```

**Programmer errors** — standard Dart errors (`ArgumentError`, etc.) for invalid arguments. These indicate bugs in your code, not runtime conditions to handle:

```dart
// These throw ArgumentError — fix your code, don't catch them:
plugin.createEvent(calendarId: '', ...);  // empty ID
plugin.createEvent(..., endDate: beforeStart);  // end before start
plugin.updateEvent(eventId: 'x');  // no fields to update
```

> **Note on error codes:**
> `DeviceCalendarError` exists for developer ergonomics and clearer `switch` handling.
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

#### Write-only access

Apps that only add events (and never read existing ones) can request the
gentler add-only prompt instead of full read/write:

```dart
final status = await plugin.requestPermissions(
  level: CalendarAccessLevel.writeOnly,
);
if (status == CalendarPermissionStatus.writeOnly ||
    status == CalendarPermissionStatus.granted) {
  // Can create events
}
```

- **iOS 17+**: shows the "Add Events Only" prompt
  (`requestWriteOnlyAccessToEvents`). Add `NSCalendarsWriteOnlyAccessUsageDescription`
  to `Info.plist`. On iOS 16 and below there is no write-only tier, so this
  falls back to a full-access request and a grant reports `granted`. Write-only
  is not a ceiling — a later `requestPermissions()` (full) re-prompts and
  upgrades the app to full access in-app if the user agrees.
- **Android**: requests only `WRITE_CALENDAR`. `WRITE_CALENDAR` and
  `READ_CALENDAR` are in the same `CALENDAR` permission group, so after a
  write-only grant a later `requestPermissions()` (full) escalates to read
  access **immediately, with no dialog** (where iOS shows a second prompt), and
  returns `granted`.

If you start with write-only and later need full read access, just call
`requestPermissions()` again — iOS shows a second prompt for the upgrade and
Android escalates silently. Either way the upgrade happens in-app; no trip to
Settings required.

#### Automatic permissions

By default you request permission yourself. To have methods request it on first
use instead, set `autoPermissions`:

```dart
// Set once, e.g. at app start.
DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;

// No explicit requestPermissions() needed — this prompts on first use, then
// throws DeviceCalendarException(permissionDenied) if access isn't granted.
await plugin.createEvent(/* ... */);
```

- `AutoPermissionMode.asNeeded` — each method asks for the minimum it needs:
  add-only operations (`createEvent`, `showCreateEventModal`) request write-only,
  everything else requests full. Defers the heavier full prompt until a read
  actually happens.
- `AutoPermissionMode.full` — request full access on the first operation that
  needs it. Simplest for apps that read regularly.
- `null` (the default) — manual: nothing prompts on its own.

Auto-permissions only act on a fresh (`notDetermined`) status — a tier you
already hold is never silently escalated. If you hold write-only and call a read
operation, you get `permissionDenied`, not a surprise prompt; call
`requestPermissions(level: CalendarAccessLevel.full)` yourself when you want to
ask for the upgrade (and to place any priming UI before it). Auto-mode prompts
at most once per access level per app run — if the user declines, later calls
throw `permissionDenied` rather than re-prompting; call `requestPermissions()`
yourself to ask again.

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
  // Raw hex string (e.g. "#FF5733")
  if (calendar.colorHex != null) {
    print('  Color: ${calendar.colorHex}');
  }
  // Or use the parsed Flutter Color directly for theming
  if (calendar.color != null) {
    // e.g. Container(color: calendar.color, ...)
  }
}

// Find a writable calendar
final writableCalendar = calendars.firstWhere(
  (cal) => !cal.readOnly,
  orElse: () => calendars.first,
);
```

### List Sources

Sources are the accounts that own calendars (iCloud, Google, local, Exchange, etc.). Use them to discover where a new calendar can live, and to target a specific account when calling `createCalendar`.

```dart
final plugin = DeviceCalendar.instance;
final sources = await plugin.listSources();

for (final source in sources) {
  print('${source.accountName} — ${source.type}');
  if (source.supportsCalendarCreation) {
    print('  ✓ can create calendars here');
  }
}

// Pick the first source that supports creation
final writable = sources.firstWhere((s) => s.supportsCalendarCreation);

// iOS: pass the source id via CreateCalendarOptionsIos
await plugin.createCalendar(
  name: 'Work',
  platformOptions: CreateCalendarOptionsIos(sourceId: writable.id),
);

// Android: pass accountName + accountType via CreateCalendarOptionsAndroid
await plugin.createCalendar(
  name: 'Work',
  platformOptions: CreateCalendarOptionsAndroid(
    accountName: writable.accountName,
    accountType: writable.accountType,
  ),
);
```

> **Note on Android**: Only sources that already have at least one calendar are returned. Freshly-added accounts won't appear until their first calendar exists.

### Create Calendar

```dart
final plugin = DeviceCalendar.instance;

// Simplest case — picks a sensible default source on each platform
final calendarId = await plugin.createCalendar(name: 'My Calendar');

// With a color
final colored = await plugin.createCalendar(
  name: 'Work',
  colorHex: '#FF5733',
);

// Target a specific account (see "List Sources" above for full example)
final scoped = await plugin.createCalendar(
  name: 'Project Calendar',
  platformOptions: CreateCalendarOptionsAndroid(accountName: 'MyApp'),
);
```

Returns the new calendar's ID. Requires write permission.

### Update Calendar

```dart
final plugin = DeviceCalendar.instance;

// Rename
await plugin.updateCalendar(calendarId, name: 'New Name');

// Recolor
await plugin.updateCalendar(calendarId, colorHex: '#3366FF');

// Both at once
await plugin.updateCalendar(
  calendarId,
  name: 'Q3 Planning',
  colorHex: '#3366FF',
);
```

At least one of `name` or `colorHex` must be provided.

### Delete Calendar

```dart
final plugin = DeviceCalendar.instance;

await plugin.deleteCalendar(calendarId);
```

Throws `DeviceCalendarException` with `DeviceCalendarError.readOnly` if the calendar can't be deleted (e.g. a system-managed account calendar).

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

// Open the native editor directly (skip the read-only viewer)
await plugin.showEventModal(event.instanceId, edit: true);
```

> **Android `edit: true` caveat:** `ACTION_EDIT` is honored inconsistently
> across calendar apps. Google Calendar ignores it for an existing event and
> opens a blank new-event editor, while the AOSP/stock calendar opens the
> editor as expected. There's no intent that reliably launches Google Calendar
> straight into edit mode on an existing event, so for a dependable edit flow
> use `showEventModal(id)` (view) and let the user tap the edit button. iOS is
> unaffected.

### Create Event via Native Editor

Opens the platform's native calendar editor in create mode. Useful when you want
the user to review/edit before saving, or as the iOS workaround for adding
attendees (which can't be done programmatically).

```dart
final plugin = DeviceCalendar.instance;

// Open blank editor
await plugin.showCreateEventModal();

// Open with pre-filled data
await plugin.showCreateEventModal(
  title: 'Team Meeting',
  startDate: DateTime.now().add(Duration(hours: 1)),
  endDate: DateTime.now().add(Duration(hours: 2)),
  location: 'Conference Room A',
  description: 'Weekly sync',
  recurrenceRule: WeeklyRecurrence(
    daysOfWeek: [DayOfWeek.tuesday],
  ),
);
```

All parameters are optional. The Future completes when the modal is dismissed
(whether the user saved or cancelled).

**Platform APIs:** iOS uses `EKEventEditViewController`, Android uses
`Intent.ACTION_INSERT`.

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

### Recurring Events

Create recurring events by passing a `RecurrenceRule` to `createEvent`. The rule types are sealed classes, so the compiler ensures you handle all cases.

```dart
// Every day for 30 days
await plugin.createEvent(
  calendarId: calendarId,
  title: 'Daily Standup',
  startDate: DateTime(2024, 3, 20, 9, 0),
  endDate: DateTime(2024, 3, 20, 9, 15),
  recurrenceRule: DailyRecurrence(end: CountEnd(30)),
);

// Every 2 weeks on Monday and Friday
await plugin.createEvent(
  calendarId: calendarId,
  title: 'Sprint Review',
  startDate: DateTime(2024, 3, 20, 14, 0),
  endDate: DateTime(2024, 3, 20, 15, 0),
  recurrenceRule: WeeklyRecurrence(
    interval: 2,
    daysOfWeek: [DayOfWeek.monday, DayOfWeek.friday],
  ),
);
```

Monthly and yearly have sealed subtypes — the default constructor is by day of month, use `.byWeekday` for weekday patterns:

```dart
// Monthly on the 1st and 15th
MonthlyRecurrence(daysOfMonth: [1, 15])

// Monthly on the 2nd Tuesday
MonthlyRecurrence.byWeekday(
  daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
)

// Monthly on the last Friday
MonthlyRecurrence.byWeekday(
  daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
)

// Yearly on Christmas
YearlyRecurrence(months: [12], daysOfMonth: [25])

// Yearly on the 4th Thursday of November (Thanksgiving)
YearlyRecurrence.byWeekday(
  months: [11],
  daysOfWeek: [RecurrenceDay(DayOfWeek.thursday, position: 4)],
)

// Last weekday of every month (uses BYSETPOS)
MonthlyRecurrence.byWeekday(
  daysOfWeek: [
    RecurrenceDay(DayOfWeek.monday),
    RecurrenceDay(DayOfWeek.tuesday),
    RecurrenceDay(DayOfWeek.wednesday),
    RecurrenceDay(DayOfWeek.thursday),
    RecurrenceDay(DayOfWeek.friday),
  ],
  setPositions: [-1],
)
```

End conditions are either a count or a date — or omit for forever:

```dart
DailyRecurrence(end: CountEnd(10))           // after 10 occurrences
DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 12, 31)))  // until a date
DailyRecurrence()                            // forever
```

When reading events back, `event.recurrenceRule` gives you the typed model. For RRULE properties the typed model doesn't cover, use the `rruleString` escape hatch — it preserves the original platform string:

```dart
final event = await plugin.getEvent(eventId);
final rule = event?.recurrenceRule;

// Typed access
if (rule is MonthlyByWeekday) {
  print(rule.daysOfWeek);
  print(rule.setPositions);
}

// Raw RRULE string — preserves platform-specific properties
// like BYHOUR or BYSETPOS combinations the typed model doesn't cover
print(rule?.rruleString); // e.g. "FREQ=MONTHLY;BYDAY=2TU;COUNT=12"
```

### Update Event

`updateEvent` updates a single thing: pass a bare event ID (`event.eventId`) to update the event — the whole series when it's recurring — or an instance ID (`event.instanceId`) to detach and edit one occurrence of a recurring series.

```dart
final plugin = DeviceCalendar.instance;

// Update event title
await plugin.updateEvent(
  eventId: event.eventId,
  title: 'Updated Meeting Title',
);

// Update multiple fields
await plugin.updateEvent(
  eventId: event.eventId,
  title: 'Team Sync',
  startDate: DateTime(2024, 3, 21, 15, 0),
  endDate: DateTime(2024, 3, 21, 16, 0),
  location: Patch.set('Conference Room B'),
  description: Patch.set('Updated description'),
  url: Patch.set('https://example.com/meeting/456'),
);

// Clear optional fields. description, location and url take a Patch:
// omit the argument to leave a field unchanged, Patch.set(...) to change it,
// Patch.clear() to remove its value.
await plugin.updateEvent(
  eventId: event.eventId,
  location: Patch.clear(),
  description: Patch.clear(),
);

// Change a timed event to all-day
await plugin.updateEvent(
  eventId: event.eventId,
  isAllDay: true,
);

// Change an all-day event to timed
await plugin.updateEvent(
  eventId: event.eventId,
  isAllDay: false,
  startDate: DateTime(2024, 3, 21, 10, 0),
  endDate: DateTime(2024, 3, 21, 11, 0),
);

// Update timezone (reinterprets local time)
// Note: "3 PM EST" becomes "3 PM PST" (different instant in time)
await plugin.updateEvent(
  eventId: event.eventId,
  timeZone: 'America/Los_Angeles',
);

// Edit only this one occurrence of a recurring event. The occurrence is
// detached from the series as an exception; startDate and endDate are
// absolute instants, so it can move to a different day.
await plugin.updateEvent(
  eventId: event.instanceId,
  title: 'Moved this week only',
  startDate: DateTime(2024, 3, 21, 15, 0),
  endDate: DateTime(2024, 3, 21, 16, 0),
);
```

### Update Recurring Events

To edit a recurring **series** — its recurrence rule, its time-of-day or duration, or any field across many occurrences — use `updateRecurring`. It takes an `EventSpan`:

- `EventSpan.allEvents` — the change applies to the whole series.
- `EventSpan.thisAndFollowing` — the series is split: the occurrence you pass, and every later one, carry the change.

```dart
final plugin = DeviceCalendar.instance;

// Change every occurrence to start at 3 PM, keeping each occurrence's date
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  startTime: EventTimeOfDay(hour: 15, minute: 0),
);

// Change the duration of all occurrences to 90 minutes
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  duration: Duration(minutes: 90),
);

// Change the whole series to weekly
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  recurrenceRule: Patch.set(WeeklyRecurrence(end: CountEnd(10))),
);

// Stop the series recurring — it becomes a single, non-recurring event
await plugin.updateRecurring(
  event.instanceId,
  EventSpan.allEvents,
  recurrenceRule: Patch.clear(),
);

// Split the series: this occurrence and every later one move to a new time.
// Returns the new series' event ID.
final newSeriesId = await plugin.updateRecurring(
  event.instanceId,
  EventSpan.thisAndFollowing,
  startTime: EventTimeOfDay(hour: 15, minute: 0),
  duration: Duration(hours: 1),
);
```

`startTime` replaces the time-of-day of every occurrence in scope while preserving each occurrence's date; `duration` sets how long each occurrence lasts (whole minutes; whole days for all-day events). `recurrenceRule` takes a `Patch`: omit it to leave recurrence unchanged, `Patch.set(...)` to change the rule, `Patch.clear()` to remove it. All other fields behave as in `updateEvent`. `updateRecurring` returns the event ID for the affected scope — the same ID for `allEvents`, the new series' ID for `thisAndFollowing`.

**Span and the split point.** For `thisAndFollowing`, pass an instance ID (`event.instanceId`) that carries an occurrence timestamp. It is the split point: that occurrence and every later one become a new series carrying the change; earlier occurrences are untouched.

**Customised occurrences.** Editing a series is best-effort with respect to occurrences a user had individually moved or deleted. Customisations before a `thisAndFollowing` split point survive; customisations at or after the split point (or anywhere, for `allEvents`) may be reset.

### Delete Event

`deleteEvent` mirrors `updateEvent`: a bare event ID deletes the event — the whole series when it's recurring — and an instance ID removes one occurrence of a recurring series.

```dart
final plugin = DeviceCalendar.instance;

// Delete an event (the whole series, if recurring)
await plugin.deleteEvent(eventId: event.eventId);

// Delete only this one occurrence, leaving the rest of the series alone
await plugin.deleteEvent(eventId: event.instanceId);
```

### Delete Recurring Events

To delete a recurring **series** outright or truncate it, use `deleteRecurring`. It takes the same `EventSpan` as `updateRecurring`:

- `EventSpan.allEvents` — the whole series is deleted (the same as `deleteEvent` with a bare event ID).
- `EventSpan.thisAndFollowing` — the occurrence you pass, and every later one, are removed; the series is truncated to end before it.

```dart
final plugin = DeviceCalendar.instance;

// Delete the whole series
await plugin.deleteRecurring(event.instanceId, EventSpan.allEvents);

// Delete this occurrence and every later one
await plugin.deleteRecurring(event.instanceId, EventSpan.thisAndFollowing);
```

For `thisAndFollowing`, pass an instance ID (`event.instanceId`) that carries an occurrence timestamp; a bare event ID throws `ArgumentError`. `allEvents` accepts either.

## 📋 Roadmap

- [x] **Permissions** — request, check, and open settings
- [x] **Calendars** — create, read, update, delete
- [x] **Events** — create, read, update, delete
- [x] **All-day events** — proper floating date handling across timezones
- [x] **Native UI** — show event modal on both platforms
- [x] **Recurring events** — create and read with sealed RecurrenceRule model (daily, weekly, monthly, yearly)
- [x] **Update recurrence rules** — change, add or remove a recurrence rule via `updateRecurring`
- [x] **Delete recurring events** — delete a whole series, this-and-following, or a single occurrence via `deleteRecurring`
- [x] **Attendees** — read-only on both platforms; use `showCreateEventModal` / `showEventModal(edit: true)` to add via native UI
- [x] **Reminders / alarms** — relative-time reminders, read/write on both platforms
- [ ] **Platform-specific extras** — organizer and other platform-native fields exposed where supported (event URL is now supported)

## 🤝 Contributing

This project is closed to outside pull requests. Bug reports and feature requests are welcome - please open an issue. The maintainer handles implementation to keep the API surface and platform-parity decisions consistent.

## 🧪 Testing Status

This plugin includes both **unit tests** and **integration tests** to ensure reliability.

## 📄 License

MIT © 2025 Bullet
See [LICENSE](LICENSE) for details.

---

**Maintained by [Bullet](https://bullet.to)** — a cross-platform task + notes + calendar app built with Flutter.