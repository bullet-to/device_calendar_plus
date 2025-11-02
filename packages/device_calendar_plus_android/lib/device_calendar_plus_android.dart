import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android implementation of [DeviceCalendarPlusPlatform].
class DeviceCalendarPlusAndroid extends DeviceCalendarPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_calendar_plus_android');

  /// Registers this class as the default instance of [DeviceCalendarPlusPlatform].
  static void registerWith() {
    DeviceCalendarPlusPlatform.instance = DeviceCalendarPlusAndroid();
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

  @override
  Future<Map<String, dynamic>?> getEvent(String instanceId) async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getEvent',
      <String, dynamic>{
        'instanceId': instanceId,
      },
    );
    return result != null ? Map<String, dynamic>.from(result) : null;
  }

  @override
  Future<void> openEvent(String instanceId, bool useModal) async {
    await methodChannel.invokeMethod<void>(
      'openEvent',
      <String, dynamic>{
        'instanceId': instanceId,
        'useModal': useModal,
      },
    );
  }
}
