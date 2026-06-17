## 0.7.0 - 2026-06-17

### Added
- Write-only access via `requestWriteOnlyAccessToEvents` (iOS 17+). It is not a
  permanent ceiling — a later full request re-prompts and upgrades the app
  in-app (#89).
- `createEvent` with no `calendarId` writes to `defaultCalendarForNewEvents`
  (#88).
- Event reminders via `EKAlarm(relativeOffset:)` on `EKEvent.alarms` (#87).

### Changed
- Simplified the permission request into a single iOS 17 availability dispatch
  (#108).

## 0.6.0 - 2026-06-16

### Changed
- **Breaking:** `updateRecurring` takes the anchored occurrence's new start
  (`newStartMillis`) instead of `startMinuteOfDay`. `shiftStart` translates the
  series anchor by the wall-clock delta (calendar-day count + time-of-day) in
  the event's `EKEvent.timeZone`, so a move can change the day and time
  together and stays correct across DST (#103).

### Behaviour
- `updateRecurring` rejects a `start` that moves the day of a series whose
  `EKRecurrenceRule` pins it (`daysOfTheWeek` / `daysOfTheMonth` /
  `monthsOfTheYear`) unless a new rule is also supplied
  (`dayMoveConflictsWithRule`).

## 0.5.2 - 2026-06-15

### Fixed
- EventKit reads and writes now run on a background serial queue instead of the
  main thread, so operations on large calendars no longer stall the UI (#79)
- `listEvents` over a span longer than EventKit's ~4-year predicate limit now
  chunks the query into windows and de-duplicates recurring instances across
  window boundaries, so long ranges return every event exactly once, sorted
  (#94)
- `createCalendar` now fails with a clear error on sources that can't hold
  calendars (e.g. subscribed/holiday sources) instead of an opaque EventKit
  failure (#96)
- `updateRecurring(thisAndFollowing, recurrenceRule: Patch.clear())` now splits
  the series — truncating the master before the occurrence and detaching a
  standalone non-recurring event at the split point — instead of collapsing the
  whole series into a single event. Matches Android's behavior (#93)

## 0.5.1 - 2026-06-15

### Fixed
- `showEventModal(edit: true)` no longer crashes with `NSInvalidArgumentException`
  ("Pushing a navigation controller is not supported"). `EKEventEditViewController`
  is a `UINavigationController` subclass and is now presented directly instead of
  being wrapped in another navigation controller (#77)

## 0.5.0 - 2026-06-11

### Changed
- **Breaking:** recurring-edit split — `updateRecurring` / `deleteRecurring`
  accept only `allEvents` and `thisAndFollowing` (both `EKSpan.futureEvents`);
  single occurrences go through `updateEvent` / `deleteEvent` with an
  occurrence timestamp (`EKSpan.thisEvent`)
- `updateRecurring` time changes preserve each occurrence's date, replacing
  only the time-of-day components

### Fixed
- Occurrence edits validate before mutating the live `EKEvent`; an edit whose
  `startDate` passes the occurrence's untouched end now fails with
  `invalidArguments` (matching Android) instead of saving an inverted event

## 0.4.0 - 2026-05-25

### Added
- `updateRecurring()` — series-level recurring-event edits with `EventSpan` (allEvents / thisAndFollowing / thisInstance), backed by `EKSpan.futureEvents` and `EKSpan.thisEvent`
- `deleteRecurring()` — same `EventSpan` semantics on `EKEventStore.remove`
- `url` field on events via `EKEvent.url`
- `Patch<T>` support in `updateEvent()` — null leaves a field unchanged, `Patch.set` writes, `Patch.clear` nils the field on the `EKEvent`
- `edit` flag on `showEvent()` — presents `EKEventEditViewController` instead of `EKEventViewController`

## 0.3.5 - 2026-04-20

### Fixed
- Calendar source lookup fallback when default source is unavailable (#13)
- `createCalendar` default fallback prefers iCloud over other CalDAV sources (#33)

## 0.3.4 - 2026-02-08

### Added
- Swift Package Manager support (CocoaPods continues to work as before)

## 0.3.3 - 2025-12-21

### Fixed
- Fixed parsing of `instanceId` for events with `@` in their event ID (e.g., Google Calendar IDs like `abc123@google.com`)

## 0.3.2 - 2025-12-19

### Changed
- `createCalendar()` signature updated to accept optional `platformOptions` parameter (ignored on iOS)

## 0.3.1 - 2025-11-07

### Fixed
- `showEvent()` now properly stores result callback and calls it in `eventViewController(_:didCompleteWith:)` delegate method after modal is dismissed

## 0.3.0 - 2024-11-05

### Changed
- **BREAKING**: `deleteEvent()` now always deletes entire series for recurring events using `EKSpan.futureEvents` on master event (removed `deleteAllInstances` parameter)
- **BREAKING**: `updateEvent()` now always updates entire series for recurring events using `EKSpan.futureEvents` on master event (removed `updateAllInstances` parameter)
- Native code now extracts event ID from instance ID format automatically and fetches master event

### Removed
- **BREAKING**: `NOT_SUPPORTED` error code (no longer needed)

## 0.2.0 - 2024-11-05

### Added
- `openAppSettings()` implementation using UIApplication.openSettingsURLString

### Removed
- **BREAKING**: `getPlatformVersion()` implementation (unused boilerplate)

## 0.1.1 - 2024-11-04

Version sync with other packages. No functional changes.

## 0.1.0 - 2024-11-04

Initial release.