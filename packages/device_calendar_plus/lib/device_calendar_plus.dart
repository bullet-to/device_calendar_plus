import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';

import 'src/calendar_permission_status.dart';
import 'src/device_calendar_error.dart';

export 'src/calendar_permission_status.dart';
export 'src/device_calendar_error.dart';

/// Main API for accessing device calendar functionality.
class DeviceCalendar {
  DeviceCalendar._(); // Prevent instantiation

  // Platform exception code for missing manifest permissions
  static const String _permissionsNotDeclared = 'PERMISSIONS_NOT_DECLARED';

  /// Returns the platform version (e.g., "Android 13", "iOS 17.0").
  static Future<String?> getPlatformVersion() {
    return DeviceCalendarPlusPlatform.instance.getPlatformVersion();
  }

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// Returns a [CalendarPermissionStatus] indicating the result:
  /// - [CalendarPermissionStatus.granted]: Full read/write access
  /// - [CalendarPermissionStatus.writeOnly]: Write-only access (iOS 17+ only)
  /// - [CalendarPermissionStatus.denied]: User denied permission
  /// - [CalendarPermissionStatus.restricted]: Blocked by device policies (iOS only)
  /// - [CalendarPermissionStatus.notDetermined]: Not yet requested (iOS only)
  ///
  /// Example:
  /// ```dart
  /// final status = await DeviceCalendar.requestPermissions();
  /// if (status == CalendarPermissionStatus.granted) {
  ///   // Access calendars
  /// } else if (status == CalendarPermissionStatus.denied) {
  ///   // Show "Enable in Settings" message
  /// } else if (status == CalendarPermissionStatus.restricted) {
  ///   // Show "Contact administrator" message
  /// }
  /// ```
  ///
  /// Throws [DeviceCalendarException] if calendar permissions are not properly
  /// configured in the app's manifest (AndroidManifest.xml or Info.plist).
  static Future<CalendarPermissionStatus> requestPermissions() async {
    try {
      final int? statusCode =
          await DeviceCalendarPlusPlatform.instance.requestPermissions();
      // Default to denied if status is null or out of range
      if (statusCode == null ||
          statusCode < 0 ||
          statusCode >= CalendarPermissionStatus.values.length) {
        return CalendarPermissionStatus.denied;
      }
      return CalendarPermissionStatus.values[statusCode];
    } on PlatformException catch (e) {
      if (e.code == _permissionsNotDeclared) {
        throw DeviceCalendarException(
          errorCode: DeviceCalendarError.permissionsNotDeclared,
          message: e.message ?? 'Calendar permissions not declared in manifest',
          details: e.details,
        );
      }
      rethrow;
    }
  }
}
