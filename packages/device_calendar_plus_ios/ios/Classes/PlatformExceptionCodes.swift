/// Platform exception codes matching PlatformExceptionCodes in Dart.
///
/// These codes are sent via method channel errors and caught/transformed
/// by the Dart layer into DeviceCalendarException.
enum PlatformExceptionCodes {
  /// Calendar usage description not declared in Info.plist.
  ///
  /// Corresponds to DeviceCalendarError.permissionsNotDeclared in Dart.
  static let permissionsNotDeclared = "PERMISSIONS_NOT_DECLARED"
  
  /// Calendar permission denied by user.
  ///
  /// Corresponds to DeviceCalendarError.permissionDenied in Dart.
  static let permissionDenied = "PERMISSION_DENIED"
  
  /// Invalid arguments passed to a method.
  ///
  /// Corresponds to DeviceCalendarError.invalidArguments in Dart.
  static let invalidArguments = "INVALID_ARGUMENTS"
  
  /// An unknown error occurred.
  ///
  /// Corresponds to DeviceCalendarError.unknown in Dart.
  static let unknownError = "UNKNOWN_ERROR"
}

