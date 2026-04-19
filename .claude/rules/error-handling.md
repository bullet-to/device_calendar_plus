# Error Handling

Two categories of errors:

## Programmer mistakes — standard Dart errors

For bugs in the caller's code caught before any platform call. Use standard
Dart error types (`ArgumentError`, `StateError`, etc.) since these indicate
code that needs fixing, not conditions to handle at runtime.

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
