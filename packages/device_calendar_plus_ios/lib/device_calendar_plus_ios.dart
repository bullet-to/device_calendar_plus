import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The iOS implementation of [DeviceCalendarPlusPlatform].
class DeviceCalendarPlusIos extends DeviceCalendarPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_calendar_plus_ios');

  /// Registers this class as the default instance of [DeviceCalendarPlusPlatform].
  static void registerWith() {
    DeviceCalendarPlusPlatform.instance = DeviceCalendarPlusIos();
  }

  @override
  Future<String?> getPlatformVersion() {
    return methodChannel.invokeMethod<String>('getPlatformVersion');
  }
}
