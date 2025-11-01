import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'device_calendar_plus_android_method_channel.dart';

abstract class DeviceCalendarPlusAndroidPlatform extends PlatformInterface {
  /// Constructs a DeviceCalendarPlusAndroidPlatform.
  DeviceCalendarPlusAndroidPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceCalendarPlusAndroidPlatform _instance = MethodChannelDeviceCalendarPlusAndroid();

  /// The default instance of [DeviceCalendarPlusAndroidPlatform] to use.
  ///
  /// Defaults to [MethodChannelDeviceCalendarPlusAndroid].
  static DeviceCalendarPlusAndroidPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DeviceCalendarPlusAndroidPlatform] when
  /// they register themselves.
  static set instance(DeviceCalendarPlusAndroidPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
