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
  Future<String?> requestPermissions() async {
    return await methodChannel.invokeMethod<String>('requestPermissions');
  }

  @override
  Future<String?> hasPermissions() async {
    return await methodChannel.invokeMethod<String>('hasPermissions');
  }

  @override
  Future<void> openAppSettings() async {
    await methodChannel.invokeMethod<void>('openAppSettings');
  }

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async {
    final result =
        await methodChannel.invokeMethod<List<dynamic>>('listCalendars');
    return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        [];
  }

  @override
  Future<String> createCalendar(
    String name,
    String? colorHex,
    CreateCalendarPlatformOptions? platformOptions,
  ) async {
    // iOS does not support platform-specific options for calendar creation
    // platformOptions is ignored
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
  Future<List<Map<String, dynamic>>> listEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'listEvents',
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
  Future<Map<String, dynamic>?> getEvent(String eventId, int? timestamp) async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getEvent',
      <String, dynamic>{
        'eventId': eventId,
        'timestamp': timestamp,
      },
    );
    return result != null ? Map<String, dynamic>.from(result) : null;
  }

  @override
  Future<void> showEventModal(String eventId, int? timestamp) async {
    await methodChannel.invokeMethod<void>(
      'showEventModal',
      <String, dynamic>{
        'eventId': eventId,
        'timestamp': timestamp,
      },
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
    String? recurrenceRule,
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
        'recurrenceRule': recurrenceRule,
      },
    );
    return result!;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    await methodChannel.invokeMethod<void>(
      'deleteEvent',
      <String, dynamic>{
        'eventId': eventId,
      },
    );
  }

  @override
  Future<void> updateEvent(
    String eventId, {
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
  }) async {
    await methodChannel.invokeMethod<void>(
      'updateEvent',
      <String, dynamic>{
        'eventId': eventId,
        'title': title,
        'startDate': startDate?.millisecondsSinceEpoch,
        'endDate': endDate?.millisecondsSinceEpoch,
        'description': description,
        'location': location,
        'isAllDay': isAllDay,
        'timeZone': timeZone,
      },
    );
  }
}
