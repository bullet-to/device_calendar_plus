<goal>
Add `showCreateEventModal` method that opens the native platform calendar editor
in create mode with optional pre-filled fields. Allows users to create events
through the system UI rather than programmatically — particularly useful as the
iOS workaround for adding attendees (which can't be done programmatically).

Plugin consumers call this from Dart. The native editor opens, the user
creates or cancels, and the Future completes.
</goal>

<background>
Federated Flutter plugin with four packages:
- `device_calendar_plus` — public Dart API
- `device_calendar_plus_platform_interface` — abstract contract
- `device_calendar_plus_android` — Android implementation (Kotlin + Dart)
- `device_calendar_plus_ios` — iOS implementation (Swift + Dart)

Existing `showEventModal(String id)` opens a native viewer for an existing
event. This new method opens the native *editor* in create mode.

Native APIs:
- iOS: `EKEventEditViewController` (create mode — set event properties on a new `EKEvent`)
- Android: `Intent.ACTION_INSERT` with extras for pre-fill

Follow the exact patterns established by `showEventModal` and `createEvent`.

Key files:
- @packages/device_calendar_plus/lib/device_calendar_plus.dart
- @packages/device_calendar_plus_platform_interface/lib/device_calendar_plus_platform_interface.dart
- @packages/device_calendar_plus_android/lib/device_calendar_plus_android.dart
- @packages/device_calendar_plus_android/android/src/main/kotlin/to/bullet/device_calendar_plus_android/DeviceCalendarPlusAndroidPlugin.kt
- @packages/device_calendar_plus_android/android/src/main/kotlin/to/bullet/device_calendar_plus_android/EventsService.kt
- @packages/device_calendar_plus_ios/lib/device_calendar_plus_ios.dart
- @packages/device_calendar_plus_ios/ios/device_calendar_plus_ios/Sources/device_calendar_plus_ios/DeviceCalendarPlusIosPlugin.swift
- @packages/device_calendar_plus_ios/ios/device_calendar_plus_ios/Sources/device_calendar_plus_ios/EventsService.swift
</background>

<user_flows>
Primary flow:
1. Developer calls `plugin.showCreateEventModal()` with optional pre-fill params
2. Native calendar editor opens (pre-filled if params provided, blank otherwise)
3. User fills in / modifies fields and saves, or cancels
4. Native editor closes
5. Future completes

Alternative flows:
- No pre-fill params: blank native editor opens
- Partial pre-fill: only provided fields are populated, rest blank

Error flows:
- Permission denied: throws `DeviceCalendarException` with `permissionDenied`
- No calendar app (Android): throws `DeviceCalendarException`
- Plugin not attached to activity (Android): throws error
</user_flows>

<requirements>
**Functional:**

1. New method `showCreateEventModal` on `DeviceCalendar` class with signature:
   ```dart
   Future<void> showCreateEventModal({
     String? title,
     DateTime? startDate,
     DateTime? endDate,
     String? description,
     String? location,
     bool? isAllDay,
     RecurrenceRule? recurrenceRule,
     EventAvailability? availability,
   })
   ```
   All parameters optional. Returns void — completes when modal is dismissed.

2. New abstract method on `DeviceCalendarPlusPlatform`:
   ```dart
   Future<void> showCreateEventModal({
     String? title,
     int? startDate,
     int? endDate,
     String? description,
     String? location,
     bool? isAllDay,
     String? recurrenceRule,
     String? availability,
   });
   ```
   DateTime converted to milliseconds, enums to strings, RecurrenceRule to RRULE
   string at the Dart API layer (matching `createEvent` pattern). Uses named params
   since all are optional (matching `updateEvent` pattern, unlike `createEvent`
   which uses positional params for required fields).

3. Android implementation uses `Intent.ACTION_INSERT` with `CalendarContract.Events.CONTENT_URI`:
   - `CalendarContract.EXTRA_EVENT_BEGIN_TIME` ← startDate (millis)
   - `CalendarContract.EXTRA_EVENT_END_TIME` ← endDate (millis)
   - `CalendarContract.Events.TITLE` ← title
   - `CalendarContract.Events.DESCRIPTION` ← description
   - `CalendarContract.Events.EVENT_LOCATION` ← location
   - `CalendarContract.Events.ALL_DAY` ← isAllDay (1/0)
   - `CalendarContract.Events.RRULE` ← recurrenceRule
   - `CalendarContract.Events.AVAILABILITY` ← availability (mapped to CalendarContract int constants)
   - Use `startActivityForResult` with a new request code (e.g. `CREATE_EVENT_REQUEST_CODE = 1002`)
   - Store result callback, complete in `onActivityResult`

4. iOS implementation uses `EKEventEditViewController` (different from existing
   `EKEventViewController` used by `showEventModal`):
   - If no pre-fill params: set `EKEventEditViewController.event = nil` — the
     controller creates a blank event on the default calendar automatically
   - If any pre-fill params: create a new `EKEvent(eventStore:)`, set properties:
     - `event.title` ← title
     - `event.startDate` ← startDate
     - `event.endDate` ← endDate
     - `event.notes` ← description
     - `event.location` ← location
     - `event.isAllDay` ← isAllDay
     - Reuse existing `parseRecurrenceRule()` from `EventsService.swift` for RRULE → `EKRecurrenceRule`
     - `event.availability` ← availability (mapped to `EKEventAvailability`)
   - Set `EKEventEditViewController.event` to the new event (or nil)
   - Set `EKEventEditViewController.eventStore` to the shared event store
   - Add `EKEventEditViewDelegate` conformance to `DeviceCalendarPlusIosPlugin`
     (this is a *different* protocol from the existing `EKEventViewDelegate`)
   - Implement `eventEditViewController(_:didCompleteWith:)` delegate method
   - Store a separate `createEventModalResult: FlutterResult?` callback
     (distinct from existing `eventModalResult` used by `showEventModal`)
   - Present modally, complete Future on delegate callback

5. Only non-null pre-fill params are set on the native side. Null params are left
   unset so the native UI shows its defaults (both platforms default to ~now + 1hr).

6. Date normalization in the Dart layer (cross-platform consistency):
   - If `isAllDay` is true and dates are provided, strip time components (midnight) — matching `createEvent` behavior
   - If no dates provided: don't default — let native editor use its own defaults
     (both platforms default to now + user's preferred duration, typically 1 hour)
   - If only `startDate` provided without `endDate`: default `endDate` to
     `startDate + 1 hour` (or `startDate + 1 day` if `isAllDay`)
   - If only `endDate` provided without `startDate`: default `startDate` to
     `endDate - 1 hour` (or `endDate - 1 day` if `isAllDay`)
   - If `endDate` is before `startDate`: throw `ArgumentError` (matching `createEvent`)

**Error Handling:**

7. `PERMISSION_DENIED` PlatformException → `DeviceCalendarException` with `permissionDenied` (both platforms)
8. Android `ActivityNotFoundException` → `DeviceCalendarException` (no calendar app)
9. Unknown PlatformExceptions rethrown unchanged (matching existing pattern)

**Edge Cases:**

10. No params at all: valid — opens blank native editor with platform defaults
</requirements>

<boundaries>
Edge cases:
- No params at all: opens completely blank native editor — valid use case
- isAllDay with time-bearing dates: strip time components before passing to native
- startDate without endDate: Dart defaults endDate to +1hr (+1day if allDay)
- endDate without startDate: Dart defaults startDate to -1hr (-1day if allDay)
- endDate before startDate: throw ArgumentError
- recurrenceRule provided without dates: pass recurrence rule, let native handle date defaults

Error scenarios:
- User cancels in native editor: Future completes normally (void), no error
- Calendar permission not granted: throws DeviceCalendarException
- Android: no calendar app installed: throws DeviceCalendarException
- iOS: unable to get root view controller: fatal (matches existing pattern)

Platform differences:
- Android availability maps to CalendarContract integer constants (0=BUSY, 1=FREE, 2=TENTATIVE)
- iOS availability maps to EKEventAvailability enum (.busy, .free, .tentative, .unavailable)
- RRULE parsing on iOS: reuse existing `parseRecurrenceRule()` in `EventsService.swift` (merged in PR #22)
</boundaries>

<implementation>
Files to create or modify:

**Dart API layer:**
- Modify `packages/device_calendar_plus/lib/device_calendar_plus.dart`
  - Add `showCreateEventModal` method with optional named params
  - Convert DateTime to millis, RecurrenceRule to RRULE string, EventAvailability to string name
  - PlatformException conversion (matching existing pattern)

**Platform interface:**
- Modify `packages/device_calendar_plus_platform_interface/lib/device_calendar_plus_platform_interface.dart`
  - Add abstract `showCreateEventModal` method

**Android Dart wrapper:**
- Modify `packages/device_calendar_plus_android/lib/device_calendar_plus_android.dart`
  - Add `showCreateEventModal` override
  - Invoke method channel `'showCreateEventModal'` with serialized params map

**Android native:**
- Modify `DeviceCalendarPlusAndroidPlugin.kt`
  - Add `"showCreateEventModal"` case in `onMethodCall`
  - Add `handleShowCreateEventModal` method
  - Add `CREATE_EVENT_REQUEST_CODE = 1002`
  - Add `createEventModalResult: Result?` field (separate from `showEventModalResult`)
  - Update `onActivityResult` to handle `CREATE_EVENT_REQUEST_CODE` branch
  - Clear `createEventModalResult` in `onDetachedFromActivity` and `onDetachedFromActivityForConfigChanges`
- Modify `EventsService.kt`
  - Add `showCreateEvent` method
  - Build `Intent.ACTION_INSERT` with extras from params
  - `startActivityForResult`

**iOS Dart wrapper:**
- Modify `packages/device_calendar_plus_ios/lib/device_calendar_plus_ios.dart`
  - Add `showCreateEventModal` override
  - Invoke method channel `'showCreateEventModal'` with serialized params map

**iOS native:**
- Modify `DeviceCalendarPlusIosPlugin.swift`
  - Add `EKEventEditViewDelegate` conformance (in addition to existing `EKEventViewDelegate`)
  - Add `"showCreateEventModal"` case in `handle` method
  - Add `handleShowCreateEventModal` method
  - Add `createEventModalResult: FlutterResult?` field (separate from `eventModalResult`)
  - Implement `eventEditViewController(_:didCompleteWith:)` delegate method
  - Present `EKEventEditViewController` modally
- Modify `EventsService.swift`
  - Add `createEventForModal` method (or similar)
  - If pre-fill params provided: create new `EKEvent`, set properties,
    reuse existing `parseRecurrenceRule()` for RRULE conversion
  - If no pre-fill params: return nil (plugin passes nil to EKEventEditViewController)
  - Return configured `EKEventEditViewController`

**Reuse existing code:**
- `PlatformExceptionConverter.convertPlatformException()` for error conversion (already shared)
- Date normalization (strip time for allDay) is currently duplicated in `createEvent`
  (line 568) and `updateEvent` (line 752). Extract into a shared helper (e.g.
  `_normalizeDate(DateTime date)`) and reuse in `showCreateEventModal`. This
  refactor is part of the implementation, not a separate task.
- iOS `parseRecurrenceRule()` in `EventsService.swift` for RRULE → EKRecurrenceRule

**Patterns to follow:**
- `showEventModal` for async result callback pattern (both platforms)
- `createEvent` for parameter serialization pattern (DateTime → millis, enum → string)
- All method channel argument maps use `<String, dynamic>` with only non-null values

**What to avoid:**
- Don't add `calendarId` param — Android `ACTION_INSERT` doesn't support pre-selecting calendar
- Don't add `attendees` param — iOS can't set them programmatically on EKEvent
- Don't return save/cancel result — keep void return matching `showEventModal`
</implementation>

<validation>
**Unit tests** (dense logic only per testing rules):

1. Dart API layer — `device_calendar_plus_test.dart`:
   - `showCreateEventModal` normalizes dates when `isAllDay` is true (strip time)
   - `showCreateEventModal` preserves exact time when `isAllDay` is false
   - `showCreateEventModal` defaults endDate to startDate + 1hr when only startDate given
   - `showCreateEventModal` defaults startDate to endDate - 1hr when only endDate given
   - `showCreateEventModal` defaults endDate to startDate + 1day when isAllDay and only startDate given
   - `showCreateEventModal` throws ArgumentError when endDate before startDate
   - `showCreateEventModal` converts PlatformException to DeviceCalendarException

2. Platform interface — add `showCreateEventModal` to mock, single registration test

3. Android/iOS platform tests — verify method channel serialization:
   - All params provided: correct method name and argument keys/values
   - No params: method called with empty/null-only map
   - Partial params: only provided values in map

**Integration tests** (backbone):

4. Both platforms (run via `run_integration_tests.sh <device-id>`):
   - `showCreateEventModal` with no params opens native editor (manual skip — can't automate native UI dismissal, same as existing `showEventModal` test)
   - Note: mark as skip with explanation, matching the existing `showEventModal` integration test pattern

**TDD approach:**
- Start with Dart API date normalization test (isAllDay stripping)
- Then error conversion test
- Then platform interface mock
- Then platform serialization tests
- Integration tests last (manual verification)
</validation>

<done_when>
1. `showCreateEventModal` callable from Dart with all optional pre-fill params
2. Android opens `ACTION_INSERT` intent with correct extras, Future completes on return
3. iOS opens `EKEventEditViewController` with pre-filled `EKEvent`, Future completes on dismiss
4. All unit tests pass (`flutter test` across all 4 packages)
5. Integration tests pass on both Android emulator and iOS simulator
6. Pre-fill params verified manually on both platforms (open modal, confirm fields populated)
</done_when>
