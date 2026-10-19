# API Design

## Cross-platform consistency

**Cross-platform first.** If both platforms can do something, it goes in the
shared API, and where they differ Android conforms to iOS (below).

**Platform-only only when the other platform genuinely can't** — and then only
through that platform's options type, passed as an `android:` or `ios:`
parameter (see *Platform-specific options*). Never add a shared field that
silently does nothing on one platform. Each platform-only field documents its
quirks on the field itself: what the platform does with it, and where it
might not stick (e.g. a synced calendar's server overwriting it).

**No parity inside the options types.** With these individual features, make
no attempt to get parity. A field in `EventOptionsAndroid` or
`CalendarOptionsIos` exposes that platform's *own* semantics and value set
directly. Don't match, map or reconcile it with a similar or overlapping field
on the other platform: no shared enums, no normalisation, no cross-platform
mapping. `EventStatusAndroid` is `CalendarContract.Events.STATUS` exactly, not
the shared `EventStatus`. If the other platform later gets a similar feature,
it gets its own type with its own semantics.

**Read-only data** is exempt: a value that only one platform provides MAY be
exposed as a nullable platform-specific field (e.g. `Event.colorHex`, which
Android reads from `EVENT_COLOR` and iOS always reports as `null`). Document
the per-platform behaviour on the field, and don't add shared write support
unless both platforms have it. A value both platforms read but only one can
write (e.g. `Event.attendees`) is written through that platform's options type,
never a shared field (see *Platform-specific options*).

When a behaviour *can* be made consistent but the platforms naturally differ,
conform Android to iOS. iOS is the priority platform — it has most of the
users and revenue — so its default behaviour sets the contract. This is
usually also the practical direction: Android's Calendar Provider is
low-level and malleable, while iOS EventKit is opinionated and hard to
change. For example, `updateRecurring`'s `thisAndFollowing` split: iOS's
`EKSpan.futureEvents` decides where the series divides, and Android's manual
`UNTIL`-truncate split is built to match it.

## Typed APIs with raw escape hatch

Use `sealed class` hierarchies for types with distinct variants (e.g.
`RecurrenceRule` → `DailyRecurrence`, `WeeklyRecurrence`). Use `enum` for
finite flat sets (`EventAvailability`, `EventStatus`).

Preserve the raw platform string alongside parsed types for lossless
round-trips (e.g. `RecurrenceRule.rruleString` keeps the original RRULE even
when parsed into a typed subset that may not cover all features).

## Immutable models

Models (`Event`, `Calendar`) are immutable with final fields, factory
constructors from maps, and value equality. No setters.

## Platform-specific options

A method that takes platform-only fields gains separate optional named
parameters, `android:` and `ios:`, each typed to that platform's own options
class (`createEvent({EventOptionsAndroid? android})`,
`createCalendar({CalendarOptionsAndroid? android, CalendarOptionsIos? ios})`).
No shared base class.

- Each applies only on its own platform and is silently ignored on the other,
  documented on the parameter, so shared code can pass both without a
  platform check. The other platform's implementation must write nothing for
  them: a call whose only change is the other platform's options is a no-op
  there.
- Only add a platform's parameter once it has a field (YAGNI). There is no
  `EventOptionsIos` until iOS has an event-only field; it is added the same
  way when it does.
- Options classes live in the platform interface, are immutable, with
  optional named fields and value equality, so adding a field later is not
  breaking.
- Create and update take separate classes (`EventOptionsAndroid`,
  `EventUpdateOptionsAndroid`). An update field follows `updateEvent`'s
  convention: plain nullable (`null` = unchanged) when the platform can't
  remove the value, a `Patch` (unchanged / set / clear) when it can.
