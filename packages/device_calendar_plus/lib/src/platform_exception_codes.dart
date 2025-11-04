/// Platform exception codes used for communication between native and Dart.
///
/// These constants ensure consistency between native platform code
/// (Kotlin/Swift) and Dart error handling.
class PlatformExceptionCodes {
  PlatformExceptionCodes._();

  // Permission-related errors

  /// Calendar permissions are not declared in the app's manifest.
  ///
  /// Android: Missing READ_CALENDAR or WRITE_CALENDAR in AndroidManifest.xml
  /// iOS: Missing NSCalendarsUsageDescription in Info.plist
  static const String permissionsNotDeclared = 'PERMISSIONS_NOT_DECLARED';

  /// Calendar permission denied by user.
  ///
  /// User has explicitly denied calendar access, or security exception occurred.
  static const String permissionDenied = 'PERMISSION_DENIED';

  // Input validation errors

  /// Invalid arguments passed to a method.
  ///
  /// Parameters are missing, of wrong type, or contain invalid values.
  static const String invalidArguments = 'INVALID_ARGUMENTS';

  // Resource errors

  /// Requested calendar or event not found.
  ///
  /// The calendar ID or event instance ID doesn't exist.
  static const String notFound = 'NOT_FOUND';

  /// Calendar is read-only and cannot be modified.
  ///
  /// Attempting to update or delete a calendar that doesn't allow modifications.
  static const String readOnly = 'READ_ONLY';

  // Operation errors

  /// Operation is not supported on this platform or in this context.
  ///
  /// Examples:
  /// - Single recurring instance updates/deletes (Android limitation)
  /// - Platform-specific feature not available
  static const String notSupported = 'NOT_SUPPORTED';

  /// Calendar operation failed.
  ///
  /// Save, update, or delete operation failed for reasons other than permissions.
  /// Check error message for details.
  static const String operationFailed = 'OPERATION_FAILED';

  // System/availability errors

  /// Calendar system is not available.
  ///
  /// Examples:
  /// - Calendar app not installed (Android)
  /// - Local calendar source not found (iOS)
  /// - Event store unavailable
  static const String calendarUnavailable = 'CALENDAR_UNAVAILABLE';

  // Generic errors

  /// An unknown or unexpected error occurred.
  ///
  /// Used for unexpected exceptions that don't fit other categories.
  /// Check error message for details.
  static const String unknownError = 'UNKNOWN_ERROR';
}
