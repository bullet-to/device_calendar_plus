import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The iOS implementation of [DeviceCalendarPlusPlatform].
///
/// Android-only options (the `android:` parameters) are ignored: iOS has no
/// counterpart to write them to.
class DeviceCalendarPlusIos extends DeviceCalendarPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_calendar_plus_ios');

  /// Registers this class as the default instance of [DeviceCalendarPlusPlatform].
  static void registerWith() {
    DeviceCalendarPlusPlatform.instance = DeviceCalendarPlusIos();
  }

  @override
  Future<String?> requestPermissions(bool writeOnly) async {
    return await methodChannel.invokeMethod<String>(
      'requestPermissions',
      <String, dynamic>{'writeOnly': writeOnly},
    );
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
  Future<List<Map<String, dynamic>>> listSources() async {
    final result =
        await methodChannel.invokeMethod<List<dynamic>>('listSources');
    return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        [];
  }

  @override
  Future<String> createCalendar(
    String name,
    String? colorHex, {
    CalendarOptionsAndroid? android,
    CalendarOptionsIos? ios,
  }) async {
    final result = await methodChannel.invokeMethod<String>(
      'createCalendar',
      <String, dynamic>{
        'name': name,
        'colorHex': colorHex,
        'sourceId': ios?.sourceId,
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
  Future<void> showEventModal(String eventId, int? timestamp,
      {bool edit = false}) async {
    await methodChannel.invokeMethod<void>(
      'showEventModal',
      <String, dynamic>{
        'eventId': eventId,
        'timestamp': timestamp,
        'edit': edit,
      },
    );
  }

  @override
  Future<String> createEvent(
    String? calendarId,
    String title,
    DateTime startDate,
    DateTime endDate,
    bool isAllDay,
    String? description,
    String? location,
    String? url,
    String? timeZone,
    String availability,
    String? recurrenceRule,
    List<int>? reminders, {
    EventOptionsAndroid? android,
  }) async {
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
        'url': url,
        'timeZone': timeZone,
        'availability': availability,
        'recurrenceRule': recurrenceRule,
        'reminders': reminders,
      },
    );
    return result!;
  }

  @override
  Future<void> deleteEvent(String eventId, {int? timestamp}) async {
    await methodChannel.invokeMethod<void>(
      'deleteEvent',
      <String, dynamic>{
        'eventId': eventId,
        'timestamp': timestamp,
      },
    );
  }

  @override
  Future<void> updateEvent(
    String eventId, {
    int? timestamp,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
    bool? isAllDay,
    String? timeZone,
    String? availability,
    Patch<List<int>>? reminders,
    EventUpdateOptionsAndroid? android,
  }) async {
    final fields = <String, dynamic>{
      'title': title,
      'startDate': startDate?.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'isAllDay': isAllDay,
      'timeZone': timeZone,
      'availability': availability,
    };
    final cleared = writePatchFields(fields, {
      'description': description,
      'location': location,
      'url': url,
      'reminders': reminders,
    });
    // A call whose only change is Android-only has nothing for iOS to write.
    // Saving no change would still detach an occurrence, so write nothing.
    if (_writesNothing(fields, cleared)) return;
    await methodChannel.invokeMethod<void>('updateEvent', <String, dynamic>{
      'eventId': eventId,
      'timestamp': timestamp,
      ...fields,
    });
  }

  @override
  Future<String> updateRecurring(
    String eventId,
    int? timestamp,
    String span, {
    String? title,
    DateTime? start,
    int? durationMinutes,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
    bool? isAllDay,
    String? timeZone,
    String? availability,
    Patch<String>? recurrenceRule,
    Patch<List<int>>? reminders,
    EventUpdateOptionsAndroid? android,
  }) async {
    final fields = <String, dynamic>{
      'title': title,
      'newStartMillis': start?.millisecondsSinceEpoch,
      'durationMinutes': durationMinutes,
      'isAllDay': isAllDay,
      'timeZone': timeZone,
      'availability': availability,
    };
    final cleared = writePatchFields(fields, {
      'description': description,
      'location': location,
      'url': url,
      'recurrenceRule': recurrenceRule,
      'reminders': reminders,
    });
    // Nothing for iOS to write, and nothing to split for thisAndFollowing:
    // the targeted scope stands.
    if (_writesNothing(fields, cleared)) return eventId;
    final result = await methodChannel.invokeMethod<String>(
      'updateRecurring',
      <String, dynamic>{
        'eventId': eventId,
        'timestamp': timestamp,
        'span': span,
        ...fields,
      },
    );
    return result!;
  }

  /// Whether an update's field changes (the payload minus the event's
  /// identity and scope) are all empty: [writePatchFields] cleared nothing,
  /// and every other entry is null. Judged from the field map itself, so a
  /// new shared field is covered automatically. [cleared] is the entry
  /// [writePatchFields] wrote, so it alone is skipped.
  static bool _writesNothing(
    Map<String, dynamic> fields,
    List<String> cleared,
  ) =>
      cleared.isEmpty &&
      fields.values.every((v) => v == null || identical(v, cleared));

  @override
  Future<void> deleteRecurring(
    String eventId,
    int? timestamp,
    String span,
  ) async {
    await methodChannel.invokeMethod<void>(
      'deleteRecurring',
      <String, dynamic>{
        'eventId': eventId,
        'timestamp': timestamp,
        'span': span,
      },
    );
  }

  @override
  Future<void> showCreateEventModal({
    String? title,
    int? startDate,
    int? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? recurrenceRule,
    String? availability,
  }) async {
    await methodChannel.invokeMethod<void>(
      'showCreateEventModal',
      <String, dynamic>{
        if (title != null) 'title': title,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (isAllDay != null) 'isAllDay': isAllDay,
        if (recurrenceRule != null) 'recurrenceRule': recurrenceRule,
        if (availability != null) 'availability': availability,
      },
    );
  }
}
