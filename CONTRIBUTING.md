# Contributing to device_calendar_plus

**This project is closed to outside pull requests.**

Bug reports and feature requests are welcome - please open an issue. I'll handle the implementation myself to keep the API surface and platform-parity decisions consistent.

If you've already started on a fix, share your approach in the issue. It's useful context and I'll credit you in the changelog when the fix ships.

The rest of this document describes the design philosophy and conventions that guide implementation decisions. It's still worth reading if you want to understand why the API looks the way it does.

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

- Don't add a field to the Dart model unless both platforms return it. **Read-only data is exempt:** a value that only one platform provides may be exposed as a nullable platform-specific field (e.g. `Event.colorHex`, which Android reads from `EVENT_COLOR` and iOS always reports as `null`). Document the per-platform behaviour on the field, and don't add write support unless both platforms have it.
- Don't change the map shape for one platform without updating the other.
- If a platform-specific field needs write configuration, handle it through typed platform option classes (see `CreateCalendarOptionsAndroid` for an example).

## Architecture

This is a federated plugin. Changes to the API surface typically touch all four packages:

1. **`device_calendar_plus_platform_interface`** — Add the method signature or parameter.
2. **`device_calendar_plus_android`** — Implement for Android (Kotlin, Calendar Provider).
3. **`device_calendar_plus_ios`** — Implement for iOS (Swift, EventKit).
4. **`device_calendar_plus`** — Expose through the public Dart API with validation and documentation.

If you're adding a new field to an existing model, you need to handle both the **write path** (Dart → native) and the **read path** (native → Dart). Both must be tested. (Read-only fields only have a read path — test that.)

## Testing

### What to test

- **Integration tests** are the backbone. They exercise the full Dart → platform channel → native API roundtrip on real devices. These live in `example/integration_test/`.
- **Unit tests** for Dart-side logic with enough branches that you can't read it and immediately know it's correct (parsing, serialization, validation). These live in each package's `test/` directory.
- **Native unit tests** for native decision logic an integration test can't set up — permission-status edge cases, for instance. Swift ones live in `packages/device_calendar_plus/example/ios/RunnerTests/`, Kotlin ones in `packages/device_calendar_plus_android/android/src/test/`.

Don't write unit tests that just assert a mock returns what you told it to return, or that verify method channel passthrough serialization in isolation — the integration tests cover those paths.

### Permission changes need a manual pass

The thin shims that call the OS permission APIs directly (`EventKitAuthorization` on iOS) sit below every seam the tests inject, so no automated layer ever reaches them — swap two EventKit request calls over and the whole suite still passes. Anything that touches them needs a human pass on a **fresh install** (delete the app first; a granted simulator returns early and never prompts), on iOS 17 or later, covering both asks:

- `requestPermissions()` — the OS shows the full-access prompt. On iOS 18 it offers three choices; check **Allow Full Access** and **Add Events Only** separately, and confirm the status that comes back matches what you tapped (`granted` / `writeOnly`) and that creating an event works without restarting the app.
- `requestPermissions(writeOnly: true)` — the OS shows the *add-only* prompt, and the status comes back `writeOnly`.

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

Swift unit tests (generate the Xcode config for a simulator build first):
```bash
cd packages/device_calendar_plus/example
flutter build ios --config-only --simulator

cd ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=<simulator>' \
  -only-testing:RunnerTests
```

Substitute any simulator you have installed for `<simulator>` — list them with
`xcrun simctl list devices available`.

That build runs `pod install`, which rewrites the Xcode project and workspace.
None of that churn belongs in a PR, so clean it up when you're done:
```bash
git checkout -- ios/Runner.xcodeproj ios/Runner.xcworkspace
```
Keep any deliberate project edits of your own (adding a test file to the
`RunnerTests` target, say) — commit those first, then discard the rest.

Kotlin unit tests (the Gradle wrapper is generated, not committed — run any
Flutter Android build once first):
```bash
cd packages/device_calendar_plus/example
flutter build apk --debug

cd android
./gradlew :device_calendar_plus_android:test
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

## Project Rules

There are Claude rules in `.claude/rules/` that document project conventions for API design, error handling, and testing. If you use Claude Code, these are loaded automatically. Otherwise, they're still worth reading — they capture decisions that apply to all contributions.
