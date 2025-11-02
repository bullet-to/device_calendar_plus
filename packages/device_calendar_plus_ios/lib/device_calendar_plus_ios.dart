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

  @override
  Future<int?> requestPermissions() async {
    return await methodChannel.invokeMethod<int>('requestPermissions');
  }

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async {
    final result =
        await methodChannel.invokeMethod<List<dynamic>>('listCalendars');
    return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        [];
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'retrieveEvents',
      <String, dynamic>{
        'startDate': startDate.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'calendarIds': calendarIds,
      },
    );
    return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        [];
  }
}
