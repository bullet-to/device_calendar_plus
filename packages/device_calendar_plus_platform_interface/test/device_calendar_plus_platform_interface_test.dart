import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> requestPermissions(bool writeOnly) async => "granted";

  @override
  Future<String?> hasPermissions() async => "granted";

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async => [];

  @override
  Future<List<Map<String, dynamic>>> listSources() async => [];

  @override
  Future<String> createCalendar(
    String name,
    String? colorHex,
    CreateCalendarPlatformOptions? platformOptions,
  ) async =>
      'mock-calendar-id';

  @override
  Future<void> updateCalendar(
      String calendarId, String? name, String? colorHex) async {}

  @override
  Future<void> deleteCalendar(String calendarId) async {}

  @override
  Future<List<Map<String, dynamic>>> listEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async =>
      [];

  @override
  Future<Map<String, dynamic>?> getEvent(
          String eventId, int? timestamp) async =>
      null;

  @override
  Future<void> showEventModal(String eventId, int? timestamp,
      {bool edit = false}) async {}

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
    List<int>? reminders,
  ) async =>
      'mock-event-id';

  @override
  Future<void> deleteEvent(String eventId, {int? timestamp}) async {}

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
  }) async {}

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
  }) async =>
      'mock-event-id';

  @override
  Future<void> deleteRecurring(
    String eventId,
    int? timestamp,
    String span,
  ) async {}

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
  }) async {}
}

void main() {
  test('can set and get custom platform instance', () {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(DeviceCalendarPlusPlatform.instance, mock);
  });
}
