# API Design

## Cross-platform consistency

Only expose features that work identically on both iOS and Android. If a
capability is read-only on one platform, it's read-only in the plugin. If it
doesn't exist on one platform, don't add it.

When a behaviour *can* be made consistent but the platforms naturally differ,
conform Android to iOS. iOS is the priority platform — it has most of the
users and revenue — so its default behaviour sets the contract. This is
usually also the practical direction: Android's Calendar Provider is
low-level and malleable, while iOS EventKit is opinionated and hard to
change. For example, `updateRecurring`'s "this and following" split has an
off-by-one in which occurrence is the boundary; iOS EventKit decides it
natively, and Android's manual split is bent to match.

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

When one platform needs extra configuration that the other doesn't, use an
abstract `PlatformOptions` class with platform-specific subclasses (e.g.
`CreateCalendarPlatformOptions` → `CreateCalendarOptionsAndroid`). This keeps
the shared API surface clean.
