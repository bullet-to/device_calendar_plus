# Upstream issue triage — builttoroam/device_calendar vs device_calendar_plus

300 issues (94 open, 206 closed) classified by 30 Haiku agents against our API digest.

**Breakdown:** 137 noise · 104 bug · 38 enhancement · 20 already-supported. (Bugs: 74 likely-affect-us, 15 unknown, 15 unlikely.)

⚠️ Classifications are a *quick* pass off issue title/body + our API digest — affectsUs is a heuristic, deep validation deferred.

---

## Enhancements we don't support yet (grouped by theme, ranked by 👍)

### Permissions — granular read-only / iOS-17 add-events-only
- **#233 (4👍, open)** — read-only permission separate from write
- **#526 (open)** — iOS 17 "Add Events Only" vs Full Access
- Our model is a single permission state; doesn't expose granular tiers.

### Custom / returned event IDs
- **#518 (3👍, open)**, #414, #128, #122 (closed), #121 (closed), #63 (closed) — let caller set the eventId on create / get it back. We auto-generate from the platform.

### Recurrence rule expansion
- **#298 (3👍, open)** — use the `rrule` package instead of a custom class
- #537 (open) multiple `dayOfMonth`; #328 (open) BYDAY valid with DAILY; #109/#147 (closed) advanced RRULE. We keep a typed subset + raw RRULE string.

### Per-event color
- **#597, #517, #458 (open)**, #265 (closed) — set color on an individual event. We only have calendar-level `colorHex`.

### Write attendees / RSVP
- **#572 (open)** status update, #333/#141/#75 (closed) add attendees on create. Attendees are read-only by design.

### Reminders / alarms
- **#105 (closed)** — event reminders/alarms. **No reminder field at all — biggest genuine feature gap.**

### Calendar change subscription
- **#180, #202 (open)** — listen for calendar changes (ContentObserver / EventKit notifications). Not in our API.

### Desktop / other platforms
- **#479 (1👍, closed)** Windows · **#409 (open)** macOS. Intentionally out of scope.

### Smaller / one-offs
- #520 holidays · #138 query events by URL/attribute · #405 calendar account email · #271 open native calendar app · #73 organizer info on Event · #425 timezone-coupling reduction · #551 EKEventStore singleton lifecycle · #610 (2👍) SwiftPM support (build infra).

### ✅ Actually already supported (Haiku mislabeled as enhancement)
- **#533** updateCalendar (name/color) — we have `updateCalendar()`
- **#491** Calendar value equality — implemented
- **#154** integration tests — we have them

---

## Bugs likely to affect us — OPEN upstream (35), ranked by 👍

| # | 👍 | area | summary |
|---|----|------|---------|
| **574** | 12 | url | URL field — *already fixed in our fork* (we store plain String). ✅ |
| **223** | 8 | calendar-crud | iOS createCalendar "Local calendar was not found" on device — same EventKit path |
| **216** | 6 | calendar-crud | Android NPE creating calendar with color — same color param surface |
| 559 | 2 | allday | iOS/Android all-day timezone inconsistency |
| 323 | 2 | allday | all-day events shift 1 day on Google/Android |
| 467 | 1 | calendar-crud | event updates not syncing to Google Calendar (Android) |
| 613 | 0 | threading | cursor leak on abnormal paths (Android) |
| 607 | 0 | calendar-crud | newly created Google calendar missing from listCalendars |
| 598 | 0 | events | crash deleting events in range |
| 596 | 0 | recurrence | "last day of month" RRULE → every day on last week |
| 591/490/420 | 0 | calendar-crud | iOS createCalendar fails on restricted/Gmail accounts (EKError 500) |
| 589/588/577/570 | 0 | recurrence | delete "this & following" instance bugs / Int→Long cast |
| 568/438 | 0 | modal | iOS modal padding; modal opens series base not instance |
| 566/530 | 0 | recurrence | RRULE parse/retrieval; recurring returned as individual events |
| 561/558/262 | 0 | permissions | iOS 17 permission state; requestFullAccessToEvents availability |
| 545 | 0 | calendar-crud | deleting 20+ events silently fails |
| 544 | 0 | calendar-crud | location not persisted on iOS |
| 542 | 0 | recurrence | crash on `RecurrenceRule(null)` |
| 535 | 0 | allday | all-day retrieved as next-day on Android |
| 534/525/452 | 0 | events | events empty on first load / wide-range query returns empty (iOS) |
| 509 | 0 | calendar-crud | eventId differs iOS vs Android |
| 477 | 0 | calendar-crud | createCalendar returns id on Android, not iOS |
| 455 | 0 | event-crud | iOS deleteEvent crash on missing UUID |
| 447 | 0 | recurrence | infinite recurrence fails on Samsung/Huawei |
| 416 | 0 | events | zero-duration midnight event not retrieved (Android) |

Plus **39 likely-affecting bugs already CLOSED upstream** — worth diffing their fixes against our code in a later validate pass (timezone, all-day boundary, recurrence split are the recurring themes).

---

## Suggested next steps
1. **Validate pass** on the high-signal open bugs — especially the recurrence-delete cluster (#570/#589/#577), all-day/timezone (#559/#535/#323), and iOS createCalendar account restrictions (#223/#591/#490/#420). These hit platform pitfalls our re-derived code can share.
2. **Top real enhancement = reminders/alarms** (#105) — the only entirely missing capability with clear demand across the calendar ecosystem.
3. Custom-eventId (#518 cluster) and granular permissions (#233/#526) are the next most-requested.
