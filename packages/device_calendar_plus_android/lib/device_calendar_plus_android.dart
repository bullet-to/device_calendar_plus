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
  Future<String> createCalendar(String name, String? colorHex) async {
    final result = await methodChannel.invokeMethod<String>(
      'createCalendar',
      <String, dynamic>{
        'name': name,
        'colorHex': colorHex,
      },
    );
    return result!;
  }

  @override
  Future<void> updateCalendar(
      String calendarId, String? name, String? colorHex) async {
    await methodChannel.invokeMethod<void>(
      'updateCalendar',
      <String, dynamic>{
        'calendarId': calendarId,
        'name': name,
        'colorHex': colorHex,
      },
    );
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    await methodChannel.invokeMethod<void>(
      'deleteCalendar',
      <String, dynamic>{'calendarId': calendarId},
    );
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
  Future<void> showEvent(String instanceId) async {
    await methodChannel.invokeMethod<void>(
      'showEvent',
      <String, dynamic>{'instanceId': instanceId},
    );
  }

  @override
  Future<String> createEvent(
    String calendarId,
    String title,
    DateTime startDate,
    DateTime endDate,
    bool isAllDay,
    String? description,
    String? location,
    String? timeZone,
    String availability,
  ) async {
    final result = await methodChannel.invokeMethod<String>(
      'createEvent',
      <String, dynamic>{
        'calendarId': calendarId,
        'title': title,
        'startDate': startDate.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'isAllDay': isAllDay,
        'description': description,
        'location': location,
        'timeZone': timeZone,
        'availability': availability,
      },
    );
    return result!;
  }

  @override
  Future<void> deleteEvent(String instanceId, bool deleteAllInstances) async {
    await methodChannel.invokeMethod<void>(
      'deleteEvent',
      <String, dynamic>{
        'instanceId': instanceId,
        'deleteAllInstances': deleteAllInstances,
      },
    );
  }

  @override
  Future<void> updateEvent(
    String instanceId,
    bool updateAllInstances, {
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
    String? availability,
  }) async {
    await methodChannel.invokeMethod<void>(
      'updateEvent',
      <String, dynamic>{
        'instanceId': instanceId,
        'updateAllInstances': updateAllInstances,
        'title': title,
        'startDate': startDate?.millisecondsSinceEpoch,
        'endDate': endDate?.millisecondsSinceEpoch,
        'description': description,
        'location': location,
        'isAllDay': isAllDay,
        'timeZone': timeZone,
        'availability': availability,
      },
    );
  }
}
