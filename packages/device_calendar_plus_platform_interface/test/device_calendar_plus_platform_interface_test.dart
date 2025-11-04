import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getPlatformVersion() async => 'Mock Platform 1.0';

  @override
  Future<int?> requestPermissions() async =>
      0; // CalendarPermissionStatus.granted

  @override
  Future<int?> hasPermissions() async => 0; // CalendarPermissionStatus.granted

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async => [];

  @override
  Future<String> createCalendar(String name, String? colorHex) async =>
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
  Future<Map<String, dynamic>?> getEvent(String instanceId) async => null;

  @override
  Future<void> showEventModal(String instanceId) async {}

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
  ) async =>
      'mock-event-id';

  @override
  Future<void> deleteEvent(String instanceId, bool deleteAllInstances) async {}

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
  }) async {}
}

void main() {
  test('can set and get custom instance', () {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(DeviceCalendarPlusPlatform.instance, mock);
  });

  test('getPlatformVersion returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(await DeviceCalendarPlusPlatform.instance.getPlatformVersion(),
        'Mock Platform 1.0');
  });

  test('requestPermissions returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(await DeviceCalendarPlusPlatform.instance.requestPermissions(), 0);
  });

  test('hasPermissions returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(await DeviceCalendarPlusPlatform.instance.hasPermissions(), 0);
  });

  test('listCalendars returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(await DeviceCalendarPlusPlatform.instance.listCalendars(), []);
  });

  test('createCalendar returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    final calendarId = await DeviceCalendarPlusPlatform.instance
        .createCalendar('Test Calendar', '#FF5733');
    expect(calendarId, equals('mock-calendar-id'));
  });

  test('updateCalendar completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance
        .updateCalendar('calendar-123', 'New Name', '#00FF00');
    // Should complete without error
  });

  test('deleteCalendar completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.deleteCalendar('calendar-123');
    // Should complete without error
  });

  test('listEvents returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    final result = await DeviceCalendarPlusPlatform.instance.listEvents(
      DateTime.now(),
      DateTime.now().add(Duration(days: 7)),
      null,
    );
    expect(result, []);
  });

  test('getEvent returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    final result =
        await DeviceCalendarPlusPlatform.instance.getEvent('event-123');
    expect(result, null);
  });

  test('showEventModal completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.showEventModal('event-123');
    // Should complete without error
  });

  test('createEvent returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    final eventId = await DeviceCalendarPlusPlatform.instance.createEvent(
      'calendar-123',
      'Team Meeting',
      DateTime(2024, 3, 15, 14, 0),
      DateTime(2024, 3, 15, 15, 0),
      false,
      'Weekly team sync',
      'Conference Room A',
      'America/New_York',
      'busy',
    );
    expect(eventId, equals('mock-event-id'));
  });

  test('deleteEvent completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.deleteEvent('event-123', false);
    // Should complete without error
  });

  test('deleteEvent with deleteAllInstances completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.deleteEvent('event-123', true);
    // Should complete without error
  });

  test('updateEvent with all parameters completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.updateEvent(
      'event-123',
      false,
      title: 'Updated Title',
      startDate: DateTime(2024, 3, 20, 10, 0),
      endDate: DateTime(2024, 3, 20, 11, 0),
      description: 'Updated description',
      location: 'Updated location',
      isAllDay: false,
      timeZone: 'America/New_York',
      availability: 'busy',
    );
    // Should complete without error
  });

  test('updateEvent with minimal parameters completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.updateEvent(
      'event-123',
      false,
      title: 'New Title',
    );
    // Should complete without error
  });

  test('updateEvent with updateAllInstances completes', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    await DeviceCalendarPlusPlatform.instance.updateEvent(
      'event-123',
      true,
      title: 'Updated Series',
    );
    // Should complete without error
  });
}
