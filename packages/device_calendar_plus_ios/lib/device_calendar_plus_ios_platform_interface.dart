import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'device_calendar_plus_ios_method_channel.dart';

abstract class DeviceCalendarPlusIosPlatform extends PlatformInterface {
  /// Constructs a DeviceCalendarPlusIosPlatform.
  DeviceCalendarPlusIosPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceCalendarPlusIosPlatform _instance = MethodChannelDeviceCalendarPlusIos();

  /// The default instance of [DeviceCalendarPlusIosPlatform] to use.
  ///
  /// Defaults to [MethodChannelDeviceCalendarPlusIos].
  static DeviceCalendarPlusIosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DeviceCalendarPlusIosPlatform] when
  /// they register themselves.
  static set instance(DeviceCalendarPlusIosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
