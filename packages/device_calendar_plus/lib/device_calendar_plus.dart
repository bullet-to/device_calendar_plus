import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';

/// Main API for accessing device calendar functionality.
class DeviceCalendar {
  DeviceCalendar._(); // Prevent instantiation

  /// Returns the platform version (e.g., "Android 13", "iOS 17.0").
  static Future<String?> getPlatformVersion() {
    return DeviceCalendarPlusPlatform.instance.getPlatformVersion();
  }
}
