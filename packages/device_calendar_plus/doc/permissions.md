# Permissions

All read/write operations require calendar permission. You can request it
yourself, or let the plugin request it on first use.

## Request and check

```dart
final plugin = DeviceCalendar.instance;

// Check the current status without prompting.
final current = await plugin.hasPermissions();

// Prompt the user (shows the system dialog the first time).
final status = await plugin.requestPermissions();
if (status != CalendarPermissionStatus.granted) return;
```

`CalendarPermissionStatus` is one of `granted`, `writeOnly`, `denied`,
`restricted`, or `notDetermined`.

When permission is denied, send the user to settings to enable it manually:

```dart
await plugin.openAppSettings();
```

## Write-only access

Apps that only add events (and never read existing ones) can request a gentler
add-only prompt:

```dart
final status = await plugin.requestPermissions(
  level: CalendarAccessLevel.writeOnly,
);
if (status == CalendarPermissionStatus.writeOnly ||
    status == CalendarPermissionStatus.granted) {
  // Can create events.
}
```

Write-only covers `createEvent` and `showCreateEventModal`. Everything else —
reading, updating, deleting, listing calendars — needs full access. Write-only
is not a ceiling: call `requestPermissions(level: CalendarAccessLevel.full)`
later to upgrade in-app.

> **iOS setup:** add `NSCalendarsWriteOnlyAccessUsageDescription` to your
> `Info.plist` (see the README install section). On iOS 16 and below there is no
> write-only tier, so the request falls back to full access and a grant reports
> `granted`.

## Automatic permissions

To have methods request permission on first use instead of doing it yourself,
set `autoPermissions` once at app start:

```dart
DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;

// Prompts on first use, then throws DeviceCalendarException(permissionDenied)
// if access isn't granted.
await plugin.createEvent(/* ... */);
```

- `AutoPermissionMode.full` — request full access on the first operation that
  needs it. Most apps read, so this is the usual choice.
- `AutoPermissionMode.asNeeded` — each method asks for the minimum it needs:
  add-only operations request write-only, everything else requests full. Use
  this for add-only apps that want to defer the full prompt.
- `null` (the default) — manual; nothing prompts on its own.

Auto-mode only prompts on a fresh (`notDetermined`) status, at most once per
access level per app run, and never silently escalates a tier you already hold.
If you hold write-only and call a read operation you get `permissionDenied` —
call `requestPermissions(level: CalendarAccessLevel.full)` yourself to ask for
the upgrade (and to place any priming UI before it).
