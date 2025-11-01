import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// An implementation of [DeviceCalendarPlusPlatform] that uses method channels.
class MethodChannelDeviceCalendarPlus extends DeviceCalendarPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_calendar_plus');

  @override
  Future<String?> getPlatformVersion() {
    return methodChannel.invokeMethod<String>('getPlatformVersion');
  }
}
