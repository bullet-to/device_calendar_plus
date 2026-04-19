<goal>
Add `listSources()` to discover available calendar sources/accounts, and allow
consumers to specify a source when creating calendars.

Plugin consumers need this when they want to create a calendar under a specific
account (e.g. Google vs iCloud) rather than relying on the automatic fallback.
</goal>

<background>
Federated Flutter plugin. `Calendar` already has `accountName`/`accountType`
fields, but there's no way to discover sources that have no calendars yet,
or to specify which source a new calendar should be created under.

Existing create calendar flow uses PR #13's tiered fallback (default calendar's
source → first CalDAV → local). This remains the default when no source is
specified.

Key files:
- @packages/device_calendar_plus/lib/src/calendar.dart
- @packages/device_calendar_plus_platform_interface/lib/src/create_calendar_options.dart
- @packages/device_calendar_plus_android/lib/src/create_calendar_options_android.dart
- @packages/device_calendar_plus_ios/ios/.../CalendarService.swift
- @packages/device_calendar_plus_android/android/.../CalendarService.kt
</background>

<requirements>
**Functional:**

1. New `CalendarSource` model:
   - `id` (String) — stable identifier for source selection
     - iOS: `EKSource.sourceIdentifier` (used by `CreateCalendarOptionsIos`)
     - Android: synthetic `"$accountName|$accountType"` — informational only,
       not used for creation. Exists for model equality/hashing. Documented as
       synthetic in dartdoc.
   - `accountName` (String) — source identifier/display name
     - iOS: `EKSource.title` (e.g. "iCloud", "Gmail")
     - Android: `ACCOUNT_NAME` (e.g. "user@gmail.com", "local")
   - `accountType` (String) — raw platform type string
     - iOS: sourceTypeToString (e.g. "caldav", "local")
     - Android: `ACCOUNT_TYPE` (e.g. "com.google", "LOCAL")
   - `type` (CalendarSourceType enum) — normalized type
   - Immutable, value equality, `fromMap`/`toMap`
   - `accountName`/`accountType` match `Calendar` model fields — consumers can
     use values from existing calendars without calling `listSources()` first

2. `CalendarSourceType` enum:
   - `local` — on-device, no sync (iOS .local, Android "LOCAL")
   - `calDav` — CalDAV protocol: iCloud, Google, Fastmail (iOS .calDAV)
   - `exchange` — Microsoft Exchange/ActiveSync (iOS .exchange)
   - `subscribed` — read-only calendar feeds (iOS .subscribed, iOS only)
   - `birthdays` — system contacts birthdays (iOS .birthdays, iOS only)
   - `other` — unknown or platform-specific sync adapters
   - Document platform availability per value (matching existing enum pattern)
   - Include `fromName` with `other` as fallback
   - Android type mapping: "LOCAL"→local, "com.google"→calDav, "com.android.exchange"→exchange, else→other

3. `listSources()` on `DeviceCalendar`:
   - Returns `List<CalendarSource>`
   - iOS: maps `eventStore.sources` to `CalendarSource` list
   - Android: queries distinct (`ACCOUNT_NAME`, `ACCOUNT_TYPE`) from `CalendarContract.Calendars`
   - PlatformException conversion (matching existing pattern)

4. Source selection on `createCalendar`:
   - Add `CreateCalendarOptionsIos` (new class) with required `sourceId` (the
     `CalendarSource.id` value, which is `EKSource.sourceIdentifier`).
     Consumers who want the default tiered fallback simply omit `platformOptions`.
   - Add optional `accountType` to `CreateCalendarOptionsAndroid` — if not
     provided, defaults to `ACCOUNT_TYPE_LOCAL` (existing behavior preserved)
   - iOS: find `EKSource` by `sourceIdentifier`, assign to calendar. If not
     found, throw `DeviceCalendarException` with `notFound`.
   - Android: set `ACCOUNT_NAME` + `ACCOUNT_TYPE` in ContentValues

5. Platform interface:
   - Add `listSources()` → `Future<List<Map<String, dynamic>>>`
   - Update `createCalendar` signature to pass source info through (via existing platformOptions)

**Error Handling:**

6. `listSources()` throws `DeviceCalendarException` with `permissionDenied` if no read access
7. iOS: `createCalendar` with unrecognized `sourceId` throws `DeviceCalendarException` with `notFound`

**Edge Cases:**

8. Source with no calendars yet: still appears in `listSources()` (iOS guarantees this; Android only shows sources that have calendars since we query the Calendars table)
9. Android: if only `accountName` is set in options (no `accountType`), default to `ACCOUNT_TYPE_LOCAL` for backward compatibility
</requirements>

<boundaries>
Edge cases:
- Empty sources list: possible on fresh device with no accounts. Return empty list.
- Subscribed/birthday sources: included in listing but creating calendars under them will fail (read-only). Don't filter — let the platform error naturally.
- Android only shows sources that already have calendars (queries Calendars table). A freshly-added account with no calendars won't appear. Document this limitation.

Platform differences:
- iOS has true source objects (`EKSource`). Android derives sources from calendar rows.
- iOS `accountName` comes from `EKSource.title` (display label like "iCloud"). Android `accountName` is `ACCOUNT_NAME` (identifier like "user@gmail.com"). Documented difference.
- `subscribed` and `birthdays` types are iOS-only (documented on enum values).
- Android may show sources that iOS doesn't (custom sync adapters → `other` type).
</boundaries>

<implementation>
Files to create:
- `packages/device_calendar_plus/lib/src/calendar_source.dart` — model + enum
- `packages/device_calendar_plus_ios/lib/src/create_calendar_options_ios.dart` — iOS platform options

Files to modify:
- `packages/device_calendar_plus/lib/device_calendar_plus.dart` — add `listSources()`, export new file
- `packages/device_calendar_plus_platform_interface/lib/device_calendar_plus_platform_interface.dart` — add abstract `listSources()`
- `packages/device_calendar_plus_android/lib/device_calendar_plus_android.dart` — implement `listSources()`
- `packages/device_calendar_plus_ios/lib/device_calendar_plus_ios.dart` — implement `listSources()`
- `packages/device_calendar_plus_android/android/.../CalendarService.kt` — add `listSources()`, update `createCalendar` to accept accountType
- `packages/device_calendar_plus_ios/ios/.../CalendarService.swift` — add `listSources()`, update `createCalendar` to accept optional `sourceId` param (find EKSource by sourceIdentifier, fall back to tiered logic if nil)
- `packages/device_calendar_plus_ios/ios/.../DeviceCalendarPlusIosPlugin.swift` — pass `sourceId` from method channel args to CalendarService
- `packages/device_calendar_plus_android/lib/src/create_calendar_options_android.dart` — add `accountType`
- `packages/device_calendar_plus_ios/lib/device_calendar_plus_ios.dart` — wire `CreateCalendarOptionsIos`
- `packages/device_calendar_plus/lib/device_calendar_plus.dart` — export `CreateCalendarOptionsIos` (matching `CreateCalendarOptionsAndroid` pattern)

Patterns to follow:
- `listCalendars()` for the listing pattern (platform returns raw maps, Dart layer converts)
- `CreateCalendarOptionsAndroid` for platform-specific options pattern
- `EventAvailability` enum for platform-documented enum pattern
</implementation>

<validation>
**Integration tests** (backbone — per testing rules):

- `listSources()` returns non-empty list on both platforms
- At least one source has type `local` or `calDav`
- Create calendar with explicit source → calendar's accountName/accountType matches
- Create calendar without source → existing behavior unchanged (tiered fallback)

No unit tests needed — the model is trivial (fromMap/toMap), and the enum
mapping is straightforward. Integration tests prove the real roundtrip.
</validation>

<done_when>
1. `listSources()` returns sources on both platforms
2. `createCalendar` with source options creates under the specified source
3. `createCalendar` without source options still uses tiered fallback
4. Integration tests pass on both Android emulator and iOS simulator
</done_when>
