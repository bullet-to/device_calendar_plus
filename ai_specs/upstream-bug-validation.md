# Upstream bug validation — deep pass

Follow-up to `upstream-issue-triage.md`. For the high-signal **open** upstream bugs flagged "likely
to affect us", an agent read the real upstream repro **and** our actual iOS/Android/Dart code to
decide whether the defect exists in *our* implementation. Every "affected" verdict was then
adversarially re-checked by a second agent.

**Result:** 28 findings · 18 not-affected · **3 affected** · 3 partially-affected · 4 needs-device-test.
All 6 adversarial verifications upheld (0 overturned). (`#574`, the 12👍 URL bug, was already
confirmed fixed in our fork in an earlier pass — not re-run here.)

---

## ✅ Confirmed bugs in our code (worth fixing)

### #596 — RRULE `BYMONTHDAY=-1` ("last day of month") is dropped — **Dart, high confidence, reproduced**
Different symptom from upstream (they corrupt it to every-weekday; we don't), but a **real bug we own**.
- `recurrence_rule.dart:321-324` (`MonthlyByDate`) and `:483-484` (`YearlyByDate`) assert
  `daysOfMonth` ∈ 1..31. RFC 5545 allows −31..−1. So a valid `BYMONTHDAY=-1` throws.
- `_RruleParser.parse` (`:723-724`) swallows the `AssertionError` and returns `null`, so
  `Event.fromMap` (`event.dart:151-153`) drops the **entire** rule *including* the preserved
  `rawRrule`.
- Reproduced via `flutter test`: `FREQ=MONTHLY;BYMONTHDAY=-1` → `null`; `BYMONTHDAY=15` → fine.
- iOS correctly emits `BYMONTHDAY=-1` (`EventsService.swift:701-704`), so it's the shared Dart
  parser that loses it — affects **both platforms**.
- **Caveat:** Dart asserts only fire in debug/profile-with-asserts/test. In a stripped **release**
  build the `-1` flows through and round-trips fine. So the severe data-loss is debug/test-only —
  but the assert is still wrong and should be widened to allow −31..−1.
- **Fix:** relax the assert to RFC 5545 range (`d >= -31 && d <= 31 && d != 0`), add a round-trip
  regression test. Cheap, self-contained.

### #452 — iOS wide date-range query silently truncated to 4 years — **iOS, high confidence**
- `EventsService.swift:82-91` calls `predicateForEvents(withStart:end:calendars:)` once with the
  caller's raw range; EventKit silently shortens any span > ~4 years to the first 4. No chunking.
- `device_calendar_plus.dart:396-398` only *documents* the limit; `listEvents` forwards the range
  unmodified.
- **Fix:** chunk wide ranges into ≤4-year windows in the iOS `retrieveEvents` loop and merge. The
  maintainer-suggested workaround upstream; we currently just document it.

### #534 — externally-synced (e.g. Google) events missing until OS syncs — **iOS, medium confidence**
- Single long-lived `EKEventStore` (`DeviceCalendarPlusIosPlugin.swift:7`), never reset/refreshed —
  grep finds zero `refreshSourcesIfNecessary()` / `reset()` calls.
- Reads run against whatever the store last synced (`EventsService.swift:91`), so server-created
  events can be absent until the OS background-syncs.
- **Fix:** call `eventStore.refreshSourcesIfNecessary()` before list/retrieve (cheap, idempotent).
  Also mitigates the iOS half of #607 and #525.

---

## 🟡 Partially affected

### #420 / #490 — iOS `createCalendar` on a restricted account (Google/Exchange) — **medium**
- Default (no-`sourceId`) path is **immune** — it picks iCloud/local (`CalendarService.swift:80-92`).
- But the explicit-`sourceId` path (`:69-78`) does **not** call `sourceSupportsCreation()` (which
  exists at `:231-237` and is only used by `listSources`), so a caller passing a Google source still
  hits EKError 500. We surface it cleanly as `operationFailed` (not an opaque crash), so it's
  recoverable — but we could reject early.
- **Fix (optional):** guard the explicit-`sourceId` path with `sourceSupportsCreation()` and throw a
  clear `readOnly`/`operationFailed` before calling `saveCalendar`.

### #530 — iOS recurring events returned as individual occurrences — **high (mostly by design)**
- Symptom (a) "returned as individual events" **does** reproduce — `events(matching:)` expands the
  series and we emit one map per occurrence — but this is **intentional**, disambiguated via
  `instanceId = eventId@startMillis` (`EventsService.swift:106-110`), unlike upstream's unhandled case.
- Symptom (b) "dayOfWeek always empty" does **not** reproduce — we emit `BYDAY` correctly
  (`:679-698`), round-trip verified. No action needed; documentation only.

---

## 🔬 Needs device/emulator test (can't decide by code reading)

- **#416** (Android) — zero-duration midnight non-all-day event. Our timed-overlap filter
  `EventsService.kt:156-157` is a strict open interval (`eventEnd > startMillis && eventBegin < endMillis`);
  a zero-duration event exactly on the query start boundary would be filtered out *if* the Instances
  provider even materialises it. Latent risk; needs a real provider test.
- **#525** (iOS) — first-launch / just-granted-permission stale snapshot. Same root as #534 (no
  refresh); whether it manifests is EventKit cache/timing dependent.
- **#561** (iOS) — iOS 17.0 `authorizationStatus` stale right after grant within the same session.
  We use the standard static read (`PermissionService.swift:27,85`); if the OS returns stale, we'd
  surface the same transient false. OS-version specific.
- **#607** (both) — new calendar missing from `listCalendars`. Android query is uncached (returns
  current device state — not our defect, it's OS sync timing). iOS shares the #534 no-refresh gap.

---

## Not affected (18) — our reimplementation already guards these
Recurrence-delete cluster **#570/#589/#588** (anchor-inclusive `UNTIL` truncate at `timestamp-1000`
removes the current occurrence; single-delete uses a `STATUS_CANCELED` exception, not RRULE
rewriting; covered by `recurrence_test.dart`) · **#577** (our API never accepts a raw int timestamp;
instance timestamps are always ms-since-epoch > 2³¹, so the `call.argument<Long>` cast never sees an
Integer — though the cast isn't defensively coerced) · **#542** (null `RecurrenceRule` is a
first-class case — nullable Dart param, `if let`/`if-else` guards on both natives → plain event) ·
all-day/timezone **#559/#535/#323** (explicit local-midnight strip on write, UTC→local-midnight on
read) · **#223/#591** (default-source fallback) · **#216** (Android color null-handling) · **#566**
(RRULE parse) · **#613/#545/#455/#544** (cursor handling, batch delete, iOS delete instance-id
guards, location persistence) · **#558** (iOS 17 `requestFullAccessToEvents` with `#available`
fallback).

---

## Recommended order of work
1. **#596** — relax the `BYMONTHDAY` assert + round-trip regression test. Smallest, clearest, real.
2. **#534 + #525/#607(iOS)** — add `refreshSourcesIfNecessary()` before iOS reads. One change, three issues.
3. **#452** — chunk iOS queries into ≤4-year windows.
4. **#420/#490** — optional early `sourceSupportsCreation()` guard on explicit-`sourceId` create.
5. **#416** — add an emulator integration test for the zero-duration-event boundary; fix the filter
   to `>=`/`<` if confirmed.

_All verdicts are from code reading + one adversarial recheck; not yet device-verified except #596
(reproduced in a Dart test)._
