<goal>
Add `updateRecurring` — a method for editing recurring events with a span
choice ("all events" vs "this and following"), resolving issue #36
(updateEvent cannot change a recurrence rule).

This is PR2. PR1 (#47, merged) landed `Patch<T>` for clearable fields on
`updateEvent`. PR2 builds on it.
</goal>

<background>
Federated Flutter plugin, four packages:
- `device_calendar_plus` — public Dart API
- `device_calendar_plus_platform_interface` — abstract contract
- `device_calendar_plus_android` — Android implementation (Kotlin + Dart)
- `device_calendar_plus_ios` — iOS implementation (Swift + Dart)

Repo: bullet-to/device_calendar_plus. Conventions in CLAUDE.md,
.claude/rules/{api-design,error-handling,testing}.md, CONTRIBUTING.md.

Today `updateEvent` always updates a whole event / whole series and cannot
change the recurrence rule at all. Issue #36 asks for recurrence-rule
editing. Investigation (device probes of EventKit and Android Calendar
Provider) established the design below.

Status of the four originating issues:
- #38 (url), #39 (compile error) — shipped in PR #42.
- #37 (calendarId in updateEvent) — closed, not planned (Android can't
  reliably move events between calendars; platform-parity).
- #36 (recurrenceRule) — THIS spec resolves it.

Issue author @SuperKrallan — credit in the CHANGELOG.
</background>

<core_principle>
"Update the recurrence" splits into a PRIMARY action and SECONDARY effects:

- PRIMARY ACTION — the rule itself changes (add / change / remove). This
  MUST behave identically on iOS and Android.
- SECONDARY EFFECTS — what happens to occurrences the user individually
  customised (moved/deleted instances, a.k.a. exceptions). These are
  BEST-EFFORT: each platform does what it naturally does, and we document
  it. We do NOT block the feature trying to make them identical.

This is consistent with the plugin's existing philosophy ("acknowledge
platform differences, don't hide them") — it just draws the line at
primary-vs-secondary.
</core_principle>

<design_decisions>
SETTLED — do not relitigate:

1. TWO methods, not one. `updateEvent` stays as-is (takes an event ID,
   handles single events + whole series, void return, no span).
   `updateRecurring` is NEW and takes an instance ID. Rationale: each
   method gets a uniform ID contract — updateEvent always an event ID,
   updateRecurring always an instance ID (`eventId@timestamp`). A single
   method would make the `eventId` param's type shift by span, which is
   the wart we are avoiding.

2. `updateRecurring(instanceId, span, {fields})` returns `Future<String>`
   — the event ID for the affected scope. Same ID for `allEvents`; the
   NEW series' ID for `thisAndFollowing` (a split creates a new event).

3. `EventUpdateSpan { allEvents, thisAndFollowing }`. Room for a future
   `thisInstanceOnly` ("this event only" single-instance edit) — NOT in
   scope now.

4. Reuses `Patch<T>` from PR1. The recurrence rule is itself a
   `Patch<RecurrenceRule>` field: `Patch.set` adds/changes the rule,
   `Patch.clear` removes it (event becomes non-recurring). `null` leaves
   recurrence untouched.

5. `updateRecurring` accepts the SAME field set as `updateEvent` (title,
   startDate, endDate, description, location, url, isAllDay, timeZone,
   availability) PLUS `recurrenceRule`. No field is span-incompatible.
   description/location/url use `Patch<String>` as in PR1.

6. `updateEvent` still accepts a recurring event's ID, behaving as
   `allEvents` (unchanged, non-breaking). Minor harmless overlap with
   `updateRecurring(instanceId, allEvents)` — two natural doors.

7. A bare event ID (no `@timestamp`) passed to `updateRecurring` with
   `span: thisAndFollowing` → `ArgumentError` (no split point).
</design_decisions>

<behaviour>
PRIMARY (identical on both platforms):
- `allEvents` — the whole series follows the new rule; or, with
  `Patch.clear()` on the rule, becomes a single event.
- `thisAndFollowing` — the series is split at the supplied instance: the
  original series is truncated to end just before that instance, and a
  new series starts at that instance with the new rule/fields.

SECONDARY (best-effort, documented in the doc comment):
- Exceptions BEFORE a `thisAndFollowing` split point survive intact
  (they remain in the truncated original's still-valid range).
- Exceptions AT/AFTER the split point (or anywhere, for `allEvents`) are
  reset: a moved occurrence persists as a detached standalone event; a
  deleted occurrence may reappear if the new rule regenerates that date.
- DB tidiness around orphaned exception rows differs between platforms
  (Android leaves orphan rows; iOS EventKit tends to clean up). Not
  user-visible. Documented, not fixed.
</behaviour>

<split_mechanics>
iOS — `EKSpan.futureEvents` performs the split natively. Fetch the
instance (not the parent), apply the new rule/fields, save with
`.futureEvents`. EventKit truncates the original and creates the new
series itself.

Android — manual. No `EKSpan` equivalent. Steps:
1. Read the parent's existing start/end; compute DURATION.
2. Truncate the parent's `RRULE` with `UNTIL=<just before split point>`.
3. Insert a new event from the split point with the new RRULE/fields.
4. Handle the `DTEND` <-> `DURATION` swap: recurring events use DURATION,
   single events use DTEND. `createEvent` already does this — mirror it.

OFF-BY-ONE: iOS's `.futureEvents` puts the anchor instance into the OLD
series, not the new one. Android's manual split is BENT TO MATCH iOS
(truncate so the anchor stays in the old series). Per the new philosophy
rule below — conform Android to iOS.
</split_mechanics>

<philosophy_rule>
Add to `.claude/rules/api-design.md`, right after the existing "platform
parity over platform power" paragraph:

"When a behaviour can be made consistent but the platforms naturally
differ, conform Android to iOS. iOS is the priority platform — it has
most of the users and revenue — so its default behaviour sets the
contract. (This is usually also the practical direction: Android's
Calendar Provider is low-level and malleable, while iOS EventKit is
opinionated and hard to change.)"

This can land in PR2 or as its own tiny docs PR.
</philosophy_rule>

<probe_findings>
From device probes during investigation (informational — not plugin code):
- iOS `.futureEvents` split works; off-by-one confirmed; exceptions
  before the split survive on the truncated parent.
- iOS exception detection via `calendarItemExternalIdentifier` does NOT
  surface detached instances for local events — irrelevant now (the
  split design doesn't need exception detection).
- Android: plain recurring events expand correctly. Creating an exception
  must use `CONTENT_EXCEPTION_URI` + DURATION (not DTEND — the provider
  rejects DTEND on an exception of a DURATION-based parent).
- Android emulator showed the parent's instances vanishing from the
  Instances table once an exception existed — almost certainly an
  emulator artifact (every real Android calendar app handles recurring
  events with exceptions). Confirm on a physical Android device before
  shipping; treat as due diligence, not a known blocker.

Throwaway probe scaffolding lives on branch
`probe/recurrence-split-validation` — do NOT merge it; it can be deleted.
</probe_findings>

<implementation>
Federated, in order (CONTRIBUTING's prescribed order):
1. platform interface — add `updateRecurring` signature + `EventUpdateSpan`.
2. android — Kotlin manual split + Dart impl.
3. ios — Swift `.futureEvents` split + Dart impl.
4. public API — `updateRecurring` with validation (ArgumentError for bare
   event ID + thisAndFollowing; at-least-one-field check) and docs.
5. `.claude/rules/api-design.md` — the philosophy rule.
6. README + CHANGELOG (CHANGELOG credits @SuperKrallan, #36).

If the PR gets large, the span machinery can be split from the recurrence
work into its own PR first.
</implementation>

<testing>
Integration tests are the backbone (.claude/rules/testing.md) — run on
real devices via `example/run_integration_tests.sh`.

Cover, on BOTH platforms:
- allEvents: change a series' rule; verify whole series follows new rule.
- allEvents: `Patch.clear()` the rule; verify event becomes single.
- thisAndFollowing: split a series; verify original truncated + new
  series from the split point with the new rule.
- thisAndFollowing: an exception before the split survives.
- ArgumentError when a bare event ID is used with thisAndFollowing.

Build env on the Mac Mini: fvm flutter at `~/fvm/versions/stable/bin/`,
Android SDK at `~/Library/Android/sdk`, AVD `dcp_probe`, JAVA_HOME at
`/Applications/Android Studio.app/Contents/jbr/Contents/Home`. Always
shut emulators/simulators down after a run.
</testing>

<open_questions>
- Android: confirm on a physical device that a rule change on an
  exception-laden series still renders correctly (the emulator was
  inconclusive). If a real device also breaks, the Android side must
  clean up orphaned exception rows as part of the update.
- Whether to split PR2 into "span machinery" + "recurrence rule" — decide
  once the diff size is visible.
</open_questions>
