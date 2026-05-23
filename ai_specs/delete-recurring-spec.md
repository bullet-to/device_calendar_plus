<goal>
Add `deleteRecurring` — deleting recurring events with a span choice
(`allEvents` / `thisAndFollowing` / `thisInstance`) — the deletion
counterpart to `updateRecurring`. Resolves the remaining half of issue #43
(single-occurrence and this-and-following *deletion*).

Also renames `EventUpdateSpan` to `EventSpan`, since the enum is now shared
by `updateRecurring` and `deleteRecurring`.
</goal>

<background>
Federated Flutter plugin, four packages: device_calendar_plus,
device_calendar_plus_platform_interface, device_calendar_plus_android,
device_calendar_plus_ios. Repo bullet-to/device_calendar_plus.

State going in (all merged to main):
- #47 — `Patch<T>` for clearable updateEvent fields.
- #48 — `updateRecurring` + `EventUpdateSpan { allEvents, thisAndFollowing,
  thisInstance }`.
- #49 — example app migrated CocoaPods -> Swift Package Manager.
- #50 — run_integration_tests.sh uses `flutter test` (not `flutter drive`).

Today `deleteEvent` deletes the WHOLE series for a recurring event; there is
no single-occurrence or this-and-following deletion. Issue #43 asked for
both editing AND deleting of individual / this-and-following events — #48
delivered the editing half; this spec closes #43 with the deletion half.

Branch: feat/delete-recurring (clone at /tmp/dcp-del). Issue author
@SuperKrallan — credit in the CHANGELOG.
</background>

<design_decisions>
SETTLED — do not relitigate:

1. NEW method `deleteRecurring(String instanceId, EventSpan span)` ->
   `Future<void>`. Mirrors `updateRecurring`'s two-method split:
   `deleteEvent` keeps a uniform contract (event ID, whole event/series);
   `deleteRecurring` takes an instance ID + a span. Do NOT add a span to
   `deleteEvent` — that reintroduces the ID-type wart #48 deliberately
   avoided.

2. `deleteEvent` is unchanged.

3. Returns `Future<void>` — there is nothing meaningful to return for a
   delete (unlike `updateRecurring`, which returns the affected event ID).

4. Rename `EventUpdateSpan` -> `EventSpan` — it is now the span of an
   operation, not specifically an update. Enum VALUES unchanged:
   `allEvents`, `thisAndFollowing`, `thisInstance`. Free to do now —
   `EventUpdateSpan` is only on main, not in a published pub.dev release.

5. Validation (mirror `updateRecurring`): empty `instanceId` ->
   `ArgumentError`; `thisAndFollowing` and `thisInstance` require an
   instance ID carrying an occurrence timestamp (`eventId@timestamp`) — a
   bare event ID -> `ArgumentError`; `allEvents` accepts a bare event ID.
</design_decisions>

<span_behaviour>
- `allEvents` — delete the whole series (what `deleteEvent` does today).
- `thisAndFollowing` — the occurrence and every later one are removed; the
  series is truncated to end before it. Earlier occurrences survive.
- `thisInstance` — only that occurrence is removed (a cancelled exception);
  the rest of the series is untouched.
</span_behaviour>

<native_mechanics>
iOS (EventsService.swift):
- `allEvents` — fetch the master via `event(withIdentifier:)`,
  `remove(span: .futureEvents)`. (Exactly what `deleteEvent` already does.)
- `thisInstance` — fetch the occurrence at `timestamp`,
  `remove(span: .thisEvent)`.
- `thisAndFollowing` — fetch the occurrence at `timestamp`,
  `remove(span: .futureEvents)`. EventKit's `.futureEvents` includes the
  fetched occurrence, consistent with `updateRecurring`'s `thisAndFollowing`
  (the anchor is in the affected scope).

Android (EventsService.kt):
- `allEvents` — `contentResolver.delete` on the event row by `_ID` (what
  `deleteEvent` already does).
- `thisInstance` — insert a CANCELLED exception: insert into
  `Events.CONTENT_EXCEPTION_URI` with `ORIGINAL_INSTANCE_TIME = timestamp`
  and `STATUS = STATUS_CANCELED`.
- `thisAndFollowing` — truncate the master's `RRULE` so the occurrence and
  all later ones stop generating: `setRruleUntil(rrule, timestamp - 1000,
  allDay)` on the master. Same truncation `updateRecurring` uses;
  `setRruleUntil` already strips `COUNT`, so a `COUNT` series converts to
  `UNTIL` cleanly. No new series is created (unlike `updateRecurring`), so
  there is no `COUNT`-adjust to do.
</native_mechanics>

<reuse_from_48>
The user asked specifically to reuse #48's machinery cleanly, not duplicate:

- `EventSpan` enum — shared by `updateRecurring` and `deleteRecurring`.
- Android — `readEventRow`, `setRruleUntil`, `formatRruleUtc`, and the
  `CONTENT_EXCEPTION_URI` insert pattern (from `updateRecurringThisInstance`)
  are already private methods on `EventsService.kt`; just call them.
- iOS — the occurrence-resolution block inside `updateRecurring` (predicate
  +/-1s, filter by `eventIdentifier`, min-by-closeness) is currently inline.
  EXTRACT it into a private helper, e.g.
  `findOccurrence(eventId:timestamp:) -> EKEvent?`, and call it from both
  `updateRecurring` and `deleteRecurring`.
- Public API — the validation pattern (empty-id check, timestamp-required-
  for-non-`allEvents` check). A shared private helper is optional; plain
  mirroring is acceptable if a helper feels forced.
- `InstanceIdParser` — already shared infrastructure.
</reuse_from_48>

<rename>
`EventUpdateSpan` -> `EventSpan`:
- Rename the file
  `device_calendar_plus/lib/src/event_update_span.dart` -> `event_span.dart`.
- Rename the enum and generalise its doc comments ("an update applies to"
  -> "an operation applies to").
- `device_calendar_plus.dart` — the `import` + `export` of the file, and the
  `updateRecurring` signature param type.
- `updateRecurring` doc comments that mention `EventUpdateSpan`.
- The platform interface `updateRecurring` takes `String span` (the enum's
  `.name`), NOT the enum — so the platform interface is unaffected.
- Tests — `device_calendar_plus_test.dart` uses `EventUpdateSpan`.
- README — the "Update Recurring Events" section references it.
- CHANGELOG — the Unreleased entry names `EventUpdateSpan`; change it to
  `EventSpan` (it never shipped, so no "renamed" note is needed).
</rename>

<implementation_order>
Federated (CONTRIBUTING order). One PR; do the rename as the first commit:
1. Rename `EventUpdateSpan` -> `EventSpan` (file + all references). Verify
   `dart analyze` + unit tests green.
2. Platform interface — add
   `Future<void> deleteRecurring(String eventId, int? timestamp, String span)`.
3. Android — `EventsService.kt` `deleteRecurring` (reusing the helpers
   above), plugin dispatch, `device_calendar_plus_android.dart` channel impl.
4. iOS — `EventsService.swift` `deleteRecurring` (with the extracted
   `findOccurrence` helper), plugin dispatch, `device_calendar_plus_ios.dart`
   channel impl.
5. Public API — `deleteRecurring` with `ArgumentError` validation and docs.
6. Tests — unit (validation), test mocks (the platform interface mock and
   the main-package mock both extend the abstract class and need the new
   method), integration tests in `recurrence_test.dart`.
7. README "Delete Recurring Events" section + CHANGELOG.

PR body: `Fixes #43` (this completes it). Draft per repo convention.
</implementation_order>

<testing>
Unit (`device_calendar_plus_test.dart`): `deleteRecurring` throws
`ArgumentError` on an empty `instanceId`, and on `thisAndFollowing` /
`thisInstance` with a bare event ID.

Integration (`recurrence_test.dart`), on BOTH platforms:
- `allEvents` — the whole series is gone.
- `thisAndFollowing` — occurrences before the anchor survive; the anchor
  and everything after are gone.
- `thisInstance` — only the anchor occurrence is gone; the rest survive.

Verify: `dart analyze`, unit tests, Android APK + iOS app compile.
Integration via `flutter test integration_test` on both platforms (#49 +
#50 enable this). Shut emulators/simulators down after each run.

Build env on the Mac Mini: fvm flutter at `~/fvm/versions/stable/bin/`,
Android SDK at `~/Library/Android/sdk`, AVD `dcp_probe`, JAVA_HOME at
`/Applications/Android Studio.app/Contents/jbr/Contents/Home`. `pod` needs
`LANG=en_US.UTF-8`. `flutter`/`adb` are not on the non-interactive PATH —
prepend `~/fvm/versions/stable/bin` and `~/Library/Android/sdk/platform-tools`.
</testing>

<notes>
- `deleteEvent` has a `TODO(breaking)` about renaming its param to `id` and
  honouring the parsed timestamp. Out of scope here — leave it.
- Pre-existing, out of scope: the README's `updateEvent` examples use
  `instanceId:` but the real parameter is `eventId:`.
</notes>
