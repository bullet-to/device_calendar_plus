import 'package:flutter/services.dart';

import 'device_calendar_error.dart';

/// Helper class for converting platform exceptions to DeviceCalendarExceptions.
class PlatformExceptionConverter {
  PlatformExceptionConverter._(); // Prevent instantiation

  // Platform exception codes
  static const String _permissionsNotDeclared = 'PERMISSIONS_NOT_DECLARED';
  static const String _permissionDenied = 'PERMISSION_DENIED';
  static const String _unknownError = 'UNKNOWN_ERROR';

  /// Converts a platform exception code string to a DeviceCalendarError enum.
  static DeviceCalendarError errorCodeFromString(String code) {
    switch (code) {
      case _permissionsNotDeclared:
        return DeviceCalendarError.permissionsNotDeclared;
      case _permissionDenied:
        return DeviceCalendarError.permissionDenied;
      case _unknownError:
        return DeviceCalendarError.unknown;
      default:
        return DeviceCalendarError.unknown;
    }
  }

  /// Converts a PlatformException to a DeviceCalendarException if it matches known codes.
  /// Returns null if the exception should be rethrown as-is.
  static DeviceCalendarException? convertPlatformException(
      PlatformException e) {
    final errorCode = errorCodeFromString(e.code);

    // Only convert known error codes
    if (e.code == _permissionsNotDeclared ||
        e.code == _permissionDenied ||
        e.code == _unknownError) {
      return DeviceCalendarException(
        errorCode: errorCode,
        message: e.message ?? 'An error occurred',
        details: e.details,
      );
    }

    return null;
  }
}
