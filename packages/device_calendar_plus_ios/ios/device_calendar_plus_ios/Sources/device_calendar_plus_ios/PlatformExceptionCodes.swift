/// Platform exception codes matching PlatformExceptionCodes in Dart.
///
/// These codes are sent via method channel errors and caught/transformed
/// by the Dart layer into DeviceCalendarException.
enum PlatformExceptionCodes {
  // Permission-related errors
  
  /// Calendar usage description not declared in Info.plist.
  ///
  /// Missing NSCalendarsUsageDescription in Info.plist
  static let permissionsNotDeclared = "PERMISSIONS_NOT_DECLARED"
  
  /// Calendar permission denied by user.
  ///
  /// User has explicitly denied calendar access, or security exception occurred.
  static let permissionDenied = "PERMISSION_DENIED"
  
  // Input validation errors
  
  /// Invalid arguments passed to a method.
  ///
  /// Parameters are missing, of wrong type, or contain invalid values.
  static let invalidArguments = "INVALID_ARGUMENTS"
  
  // Resource errors
  
  /// Requested calendar or event not found.
  ///
  /// The calendar ID or event instance ID doesn't exist.
  static let notFound = "NOT_FOUND"
  
  /// Calendar is read-only and cannot be modified.
  ///
  /// Attempting to update or delete a calendar that doesn't allow modifications.
  static let readOnly = "READ_ONLY"
  
  // Operation errors
  
  /// Calendar operation failed.
  ///
  /// Save, update, or delete operation failed for reasons other than permissions.
  /// Check error message for details.
  static let operationFailed = "OPERATION_FAILED"
  
  // System/availability errors
  
  /// Calendar system is not available.
  ///
  /// Examples:
  /// - Local calendar source not found
  /// - Event store unavailable
  static let calendarUnavailable = "CALENDAR_UNAVAILABLE"
  
  // Generic errors
  
  /// An unknown or unexpected error occurred.
  ///
  /// Used for unexpected exceptions that don't fit other categories.
  /// Check error message for details.
  static let unknownError = "UNKNOWN_ERROR"
}

