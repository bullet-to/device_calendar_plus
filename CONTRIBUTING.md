# Contributing to device_calendar_plus

Contributions are welcome! Please open an issue first for larger features or breaking changes so we can align on approach before code is written.

## Design Philosophy

This plugin prioritises **correctness and consistency over flexibility**. A few principles guide decision-making:

- **Calendar semantics, not database semantics.** Decisions should reflect how calendars actually work. All-day events are floating calendar dates, not instants in time. "January 15" means January 15 regardless of timezone.
- **Platform parity over platform power.** If a behaviour can't be made consistent across iOS and Android, we restrict the API rather than expose divergent behaviour. For example, recurring event updates always affect the entire series because not all platforms support single-instance modification.
- **Acknowledge platform differences, don't hide them.** Where platforms genuinely differ (iOS write-only permissions, Android account-based calendars), we surface that through typed options and documented enum values rather than papering over it.
- **Keep native code thin.** Business logic and data transformation belong in Dart where it's easier to test and maintain. Native code should focus on platform API calls and return raw data for Dart to process.

## DateTime Conventions

These conventions apply across the entire plugin. Any new feature that deals with dates must follow them.

- **All DateTimes cross the method channel as millisecondsSinceEpoch** (integers). Dart handles conversion to/from DateTime objects.
- **Event end dates use half-open intervals** `[start, end)`. The end date is the first moment *after* the event. A 1-hour meeting from 3pm has `endDate` of 4pm. An all-day event on January 15 has `startDate` Jan 15 00:00 and `endDate` Jan 16 00:00.
- **All-day events are floating dates.** They represent calendar dates, not instants in time. Do not convert them to UTC. The date components (year, month, day) must be preserved across timezone changes.
- **Timed events are instants.** They represent specific moments and can be freely converted to UTC.

## Platform Interface Contract

Both platform implementations must return data in the **same map shape**. The platform interface defines this contract — if a field exists in the Dart model's `fromMap()`, both platforms must populate it.

- Don't add a field to the Dart model unless both platforms return it.
- Don't change the map shape for one platform without updating the other.
- If a field is platform-specific, handle it through typed platform option classes (see `CreateCalendarOptionsAndroid` for an example).

## Architecture

This is a federated plugin. Changes to the API surface typically touch all four packages:

1. **`device_calendar_plus_platform_interface`** — Add the method signature or parameter.
2. **`device_calendar_plus_android`** — Implement for Android (Kotlin, Calendar Provider).
3. **`device_calendar_plus_ios`** — Implement for iOS (Swift, EventKit).
4. **`device_calendar_plus`** — Expose through the public Dart API with validation and documentation.

If you're adding a new field to an existing model, you need to handle both the **write path** (Dart → native) and the **read path** (native → Dart). Both must be tested.

## Testing

### What to test

- **Unit tests** for any Dart-side logic (parsing, serialization, validation). These live in each package's `test/` directory.
- **Mock-based tests** for the public API layer, verifying arguments are passed correctly to the platform and results are converted correctly from it.
- **Integration tests** for end-to-end behaviour on real devices. These live in `example/integration_test/`.

### Write and read paths

When adding a new feature or field, test both directions:

- **Write path:** Verify the value is passed from the Dart API through to the platform call with correct serialization.
- **Read path:** Verify the value returned by the platform is correctly deserialized into the Dart model.

A field that is written but never read back (or vice versa) is a bug.

### Running tests

Unit tests (all packages):
```bash
very_good test --recursive
```

Integration tests:
```bash
cd example
./run_integration_tests.sh <device-id>
```

## Pull Requests

- **One feature per PR.** Each PR should branch off `main` and contain only its own changes.
- **Don't include version bumps.** Version bumps are handled by the maintainer at release time.
- **Update documentation.** If your change affects the public API, update the package README with usage examples.
- **All tests must pass** before requesting review.

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add support for recurring events
fix: correct timezone handling for all-day events
docs: update API documentation
test: add integration tests for event creation
refactor: simplify permission handling
```

## Code Style

- Run `dart format .` before committing.
- Follow existing patterns in the codebase. Look at how similar features are implemented before starting.
- Use `const` constructors and immutable models where possible.
- Enums should have safe factory methods with fallback defaults for unrecognised values.
- Validate inputs with `ArgumentError` at the Dart API boundary, before calling into the platform.
