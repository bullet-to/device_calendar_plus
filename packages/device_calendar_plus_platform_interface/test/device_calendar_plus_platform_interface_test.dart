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
  Future<List<Map<String, dynamic>>> listCalendars() async => [];

  @override
  Future<List<Map<String, dynamic>>> retrieveEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async =>
      [];

  @override
  Future<Map<String, dynamic>?> getEvent(
    String eventId,
    DateTime? occurrenceDate,
  ) async =>
      null;
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

  test('listCalendars returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(await DeviceCalendarPlusPlatform.instance.listCalendars(), []);
  });

  test('retrieveEvents returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    final result = await DeviceCalendarPlusPlatform.instance.retrieveEvents(
      DateTime.now(),
      DateTime.now().add(Duration(days: 7)),
      null,
    );
    expect(result, []);
  });

  test('getEvent returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    final result = await DeviceCalendarPlusPlatform.instance.getEvent(
      'event-123',
      null,
    );
    expect(result, null);
  });
}
