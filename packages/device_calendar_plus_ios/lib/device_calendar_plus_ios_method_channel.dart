import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_calendar_plus_ios_platform_interface.dart';

/// An implementation of [DeviceCalendarPlusIosPlatform] that uses method channels.
class MethodChannelDeviceCalendarPlusIos extends DeviceCalendarPlusIosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_calendar_plus_ios');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
