import 'package:device_calendar_plus_platform_interface/src/method_channel_device_calendar_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

export 'src/method_channel_device_calendar_plus.dart';

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

  static DeviceCalendarPlusPlatform _instance =
      MethodChannelDeviceCalendarPlus();

  /// The default instance of [DeviceCalendarPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelDeviceCalendarPlus].
  static DeviceCalendarPlusPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [DeviceCalendarPlusPlatform] when they register themselves.
  static set instance(DeviceCalendarPlusPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Returns the platform version.
  Future<String?> getPlatformVersion();
}
