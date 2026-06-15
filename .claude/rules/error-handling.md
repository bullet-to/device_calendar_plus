# Error Handling

Two categories of errors:

## Programmer mistakes — standard Dart errors

For bugs in the caller's code caught before any platform call. Use standard
Dart error types (`ArgumentError`, `StateError`, etc.) since these indicate
code that needs fixing, not conditions to handle at runtime.

### Throw for *invalid* input, not *degenerate-but-valid* input

Reserve `ArgumentError` for arguments the method genuinely cannot act on —
where **no correct behavior exists**: `endDate` before `startDate`, an empty
`eventId` that targets nothing, two contradictory arguments. Do **not** throw
when the input has a single obvious, harmless interpretation — produce that
result instead.

The test: *does a well-defined, valid outcome exist for this input?* If yes,
return it rather than throwing.

- An update call with no changed fields → **no-op**: return without a platform
  write. The post-condition ("the event matches the requested values") is
  already satisfied. Don't throw "at least one field must be provided".
- An empty collection argument → act on nothing, like `List.addAll([])`.

This follows from the category above: an `ArgumentError` flags code that needs
*fixing* and is not meant to be caught. A no-change save is a legitimate
runtime state (the user opened an editor and pressed Save without editing), so
rejecting it forces callers into defensive `try/catch` for a benign case.
Mutation APIs should be idempotent under "no change".

## Runtime errors — `DeviceCalendarException`

For errors from the native platform that callers should handle at runtime.
Converted from `PlatformException` via `PlatformExceptionConverter`.

Error codes defined in `DeviceCalendarError` enum: `permissionDenied`,
`notFound`, `readOnly`, `operationFailed`, etc.

Pattern in every public method:

```dart
try {
  await DeviceCalendarPlusPlatform.instance.someMethod(...);
} on PlatformException catch (e, stackTrace) {
  final converted = PlatformExceptionConverter.convertPlatformException(e);
  if (converted != null) {
    Error.throwWithStackTrace(converted, stackTrace);
  }
  rethrow;
}
```

Unrecognized `PlatformException` codes are rethrown unchanged.
