import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';

import 'src/calendar.dart';
import 'src/calendar_permission_status.dart';
import 'src/device_calendar_error.dart';

export 'src/calendar.dart';
export 'src/calendar_permission_status.dart';
export 'src/device_calendar_error.dart';

/// Main API for accessing device calendar functionality.
class DeviceCalendarPlugin {
  DeviceCalendarPlugin._(); // Prevent instantiation

  // Platform exception codes
  static const String _permissionsNotDeclared = 'PERMISSIONS_NOT_DECLARED';
  static const String _permissionDenied = 'PERMISSION_DENIED';

  /// Returns the platform version (e.g., "Android 13", "iOS 17.0").
  static Future<String?> getPlatformVersion() {
    return DeviceCalendarPlusPlatform.instance.getPlatformVersion();
  }

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// Returns a [CalendarPermissionStatus] indicating the result
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

  /// Lists all calendars available on the device.
  ///
  /// Returns a list of [Calendar] objects representing each calendar.
  ///
  /// Example:
  /// ```dart
  /// final calendars = await DeviceCalendarPlugin.listCalendars();
  /// for (final calendar in calendars) {
  ///   print('${calendar.name} (${calendar.id})');
  ///   print('  Read-only: ${calendar.readOnly}');
  ///   print('  Primary: ${calendar.isPrimary}');
  ///   print('  Color: ${calendar.colorHex}');
  /// }
  /// ```
  static Future<List<Calendar>> listCalendars() async {
    try {
      final List<Map<String, dynamic>> rawCalendars =
          await DeviceCalendarPlusPlatform.instance.listCalendars();
      return rawCalendars.map((map) => Calendar.fromMap(map)).toList();
    } on PlatformException catch (e) {
      if (e.code == _permissionDenied) {
        throw DeviceCalendarException(
          errorCode: DeviceCalendarError.permissionDenied,
          message: e.message ?? 'Calendar permission denied',
          details: e.details,
        );
      }
      rethrow;
    }
  }
}
