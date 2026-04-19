# Testing Principles

For a Flutter federated plugin that bridges Dart to native calendar APIs.

## Test layers

### Integration tests (backbone)

On-device tests that exercise the full Dart -> platform channel -> native API ->
real calendar roundtrip. These are the most valuable tests for this plugin.

Run via `run_integration_tests.sh <device-id>` on simulators/emulators.
Always run on both Android and iOS — platform behavior differs. Pass a device
ID to skip interactive selection (e.g. `emulator-5554` for Android, a simulator
UUID for iOS). Without an argument it prompts interactively.

Good candidates:
- CRUD flows: create event, read it back, verify fields match
- Permission handling: denied, granted, write-only
- Recurring events: create with RRULE, verify instances appear
- Edge cases that only surface on real devices (timezone handling, all-day
  events spanning midnight, platform-specific date quirks)

### Unit tests (dense logic only)

Only for code with enough branches that you can't read it and immediately know
it's correct:

- Recurrence rule parsing / serialization (RRULE string <-> typed objects)
- Date normalization (all-day event time stripping)
- Instance ID parsing (eventId@timestamp format)
- Validation logic (argument checks, enum conversion)
- PlatformException -> DeviceCalendarException conversion

Don't unit-test:
- Trivial getters, constructors, or model properties
- Platform method channel passthrough (the integration tests cover this)
- Mock plumbing ("mock returns X, assert X comes back")
- Methods that just delegate to the platform interface

### Property tests (invariants)

Verify rules that must hold for all inputs:

- Serialization roundtrips: RecurrenceRule -> RRULE string -> RecurrenceRule
- ID roundtrips: instanceId -> parse -> reconstruct returns same ID

## When to add a test

Grow the suite from pain, not from a ratio target:

1. A bug was fixed - always add a regression test that would have caught it.
2. Logic is complex enough that you can't read it and immediately know it's
   correct.
3. An integration test failed and you couldn't locate the bug quickly - add a
   smaller unit test.

## TDD execution discipline

When writing tests, use vertical-slice TDD:

1. Write exactly **one** failing test for the next behavior
2. Write the **minimum** code to make it pass
3. Refactor while all tests are green
4. Commit; repeat

Rules:
- Never write multiple tests before implementing
- Never implement ahead of tests
- Never refactor while a test is failing
- Tests exercise public interfaces, not internal implementation

## Test structure

Organise tests by class, then method, then behaviour:

```
ClassName
  methodName
    should do X when Y
    should throw when Z
```

## What not to test

- Platform method channel serialization in isolation (integration tests cover
  the real path)
- That a mock returns what you told it to return
- "Completes without error" on void methods with no logic
- Third-party library internals
- Private helpers with obvious behavior
- Glue code that just passes values through
