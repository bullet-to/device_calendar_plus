import 'package:flutter/services.dart';

import 'device_calendar_error.dart';
import 'platform_exception_codes.dart';

/// Helper class for converting platform exceptions to DeviceCalendarExceptions.
class PlatformExceptionConverter {
  PlatformExceptionConverter._(); // Prevent instantiation

  /// Converts a platform exception code string to a DeviceCalendarError enum.
  ///
  /// Returns null for unrecognized error codes.
  static DeviceCalendarError? errorCodeFromString(String code) {
    switch (code) {
      case PlatformExceptionCodes.permissionsNotDeclared:
        return DeviceCalendarError.permissionsNotDeclared;
      case PlatformExceptionCodes.permissionDenied:
        return DeviceCalendarError.permissionDenied;
      case PlatformExceptionCodes.invalidArguments:
        return DeviceCalendarError.invalidArguments;
      case PlatformExceptionCodes.notFound:
        return DeviceCalendarError.notFound;
      case PlatformExceptionCodes.readOnly:
        return DeviceCalendarError.readOnly;
      case PlatformExceptionCodes.notSupported:
        return DeviceCalendarError.notSupported;
      case PlatformExceptionCodes.operationFailed:
        return DeviceCalendarError.operationFailed;
      case PlatformExceptionCodes.calendarUnavailable:
        return DeviceCalendarError.calendarUnavailable;
      case PlatformExceptionCodes.unknownError:
        return DeviceCalendarError.unknown;
      default:
        return null;
    }
  }

  /// Converts a PlatformException to a DeviceCalendarException if it matches known codes.
  /// Returns null if the exception should be rethrown as-is.
  static DeviceCalendarException? convertPlatformException(
      PlatformException e) {
    final errorCode = errorCodeFromString(e.code);

    // Only convert recognized error codes
    if (errorCode != null) {
      return DeviceCalendarException(
        errorCode: errorCode,
        message: e.message ?? 'An error occurred',
        details: e.details,
      );
    }

    return null;
  }
}
