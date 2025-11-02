import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface that implementations of device_calendar_plus must implement.
///
/// Platform implementations should extend this class rather than implement it
/// as `DeviceCalendar`. Extending this class (using `extends`) ensures that
/// the subclass will get the default implementation, while platform
/// implementations that `implements` this interface will be broken by newly
/// added [DeviceCalendarPlusPlatform] methods.
abstract class DeviceCalendarPlusPlatform extends PlatformInterface {
  DeviceCalendarPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceCalendarPlusPlatform? _instance;

  /// The default instance of [DeviceCalendarPlusPlatform] to use.
  ///
  /// Platform-specific implementations (Android/iOS) set this automatically.
  static DeviceCalendarPlusPlatform get instance {
    if (_instance == null) {
      throw StateError(
        'DeviceCalendarPlusPlatform.instance has not been initialized. '
        'This should never happen in production as platform-specific '
        'implementations register themselves automatically.',
      );
    }
    return _instance!;
  }

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [DeviceCalendarPlusPlatform] when they register themselves.
  static set instance(DeviceCalendarPlusPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Returns the platform version.
  Future<String?> getPlatformVersion();

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// Returns the raw integer status code from the platform.
  /// The main API layer converts this to [CalendarPermissionStatus].
  Future<int?> requestPermissions();

  /// Lists all calendars available on the device.
  ///
  /// Returns a list of calendar data as maps. The main API layer
  /// converts these to [DeviceCalendar] objects.
  Future<List<Map<String, dynamic>>> listCalendars();
}
