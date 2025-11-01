import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_calendar_plus_android_platform_interface.dart';

/// An implementation of [DeviceCalendarPlusAndroidPlatform] that uses method channels.
class MethodChannelDeviceCalendarPlusAndroid extends DeviceCalendarPlusAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_calendar_plus_android');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
