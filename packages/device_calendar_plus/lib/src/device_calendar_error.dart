/// Error codes for device calendar operations.
enum DeviceCalendarError {
  // Permission-related errors

  /// Calendar permissions are not declared in the app's manifest.
  ///
  /// On Android: Missing READ_CALENDAR or WRITE_CALENDAR in AndroidManifest.xml
  /// On iOS: Missing NSCalendarsUsageDescription in Info.plist
  permissionsNotDeclared,

  /// Calendar permission was denied by the user.
  permissionDenied,

  // Input validation errors

  /// Invalid arguments were passed to a method.
  invalidArguments,

  // Resource errors

  /// Requested calendar or event not found.
  notFound,

  /// Calendar is read-only and cannot be modified.
  readOnly,

  // Operation errors

  /// Calendar operation failed.
  operationFailed,

  // System/availability errors

  /// Calendar system is not available.
  calendarUnavailable,

  // Generic errors

  /// An unknown error occurred.
  unknown,
}

/// Exception thrown by device calendar operations.
class DeviceCalendarException implements Exception {
  /// The error code describing what went wrong.
  final DeviceCalendarError errorCode;

  /// A human-readable error message.
  final String message;

  /// Optional additional details about the error.
  final dynamic details;

  const DeviceCalendarException({
    required this.errorCode,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'DeviceCalendarException($errorCode): $message';
}
