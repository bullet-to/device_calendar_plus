import 'package:device_calendar_plus_android/device_calendar_plus_android.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceCalendarPlusAndroid', () {
    const kPlatformVersion = 'Android 13';
    late DeviceCalendarPlusAndroid plugin;
    late List<MethodCall> log;

    setUp(() async {
      plugin = DeviceCalendarPlusAndroid();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin.methodChannel, (methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'getPlatformVersion':
            return kPlatformVersion;
          case 'requestPermissions':
            return 0; // CalendarPermissionStatus.granted
          case 'listCalendars':
            return [
              {
                'id': '1',
                'name': 'Work',
                'readOnly': false,
                'isPrimary': true,
                'hidden': false,
              }
            ];
          case 'createCalendar':
            return 'android-calendar-id-456';
          case 'updateCalendar':
            return null;
          case 'deleteCalendar':
            return null;
          case 'retrieveEvents':
            return [
              {
                'eventId': 'event1',
                'calendarId': 'cal1',
                'title': 'Test Event',
                'startDate': DateTime.now().millisecondsSinceEpoch,
                'endDate': DateTime.now().millisecondsSinceEpoch,
                'isAllDay': false,
                'availability': 'busy',
                'status': 'confirmed',
              }
            ];
          case 'createEvent':
            return 'android-event-id-789';
          case 'deleteEvent':
            return null;
          default:
            return null;
        }
      });
    });

    test('can be registered', () {
      DeviceCalendarPlusAndroid.registerWith();
      expect(DeviceCalendarPlusPlatform.instance,
          isA<DeviceCalendarPlusAndroid>());
    });

    test('getPlatformVersion returns correct version', () async {
      final version = await plugin.getPlatformVersion();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformVersion', arguments: null)],
      );
      expect(version, equals(kPlatformVersion));
    });

    test('requestPermissions returns granted status', () async {
      final status = await plugin.requestPermissions();
      expect(
        log,
        <Matcher>[isMethodCall('requestPermissions', arguments: null)],
      );
      expect(status, equals(0)); // CalendarPermissionStatus.granted
    });

    test('listCalendars returns list of calendars', () async {
      final calendars = await plugin.listCalendars();
      expect(
        log,
        <Matcher>[isMethodCall('listCalendars', arguments: null)],
      );
      expect(calendars, hasLength(1));
      expect(calendars[0]['id'], equals('1'));
      expect(calendars[0]['name'], equals('Work'));
    });

    test('createCalendar with name only', () async {
      final calendarId = await plugin.createCalendar('My Calendar', null);

      expect(log.length, equals(1));
      expect(log[0].method, equals('createCalendar'));
      expect(log[0].arguments['name'], equals('My Calendar'));
      expect(log[0].arguments['colorHex'], isNull);
      expect(calendarId, equals('android-calendar-id-456'));
    });

    test('createCalendar with name and color', () async {
      final calendarId =
          await plugin.createCalendar('Work Calendar', '#FF5733');

      expect(log.length, equals(1));
      expect(log[0].method, equals('createCalendar'));
      expect(log[0].arguments['name'], equals('Work Calendar'));
      expect(log[0].arguments['colorHex'], equals('#FF5733'));
      expect(calendarId, equals('android-calendar-id-456'));
    });

    test('updateCalendar with name only', () async {
      await plugin.updateCalendar('cal-456', 'Updated Name', null);

      expect(log.length, equals(1));
      expect(log[0].method, equals('updateCalendar'));
      expect(log[0].arguments['calendarId'], equals('cal-456'));
      expect(log[0].arguments['name'], equals('Updated Name'));
      expect(log[0].arguments['colorHex'], isNull);
    });

    test('updateCalendar with name and color', () async {
      await plugin.updateCalendar('cal-456', 'Updated Name', '#00FF00');

      expect(log.length, equals(1));
      expect(log[0].method, equals('updateCalendar'));
      expect(log[0].arguments['calendarId'], equals('cal-456'));
      expect(log[0].arguments['name'], equals('Updated Name'));
      expect(log[0].arguments['colorHex'], equals('#00FF00'));
    });

    test('deleteCalendar calls method with correct arguments', () async {
      await plugin.deleteCalendar('cal-456');

      expect(log.length, equals(1));
      expect(log[0].method, equals('deleteCalendar'));
      expect(log[0].arguments['calendarId'], equals('cal-456'));
    });

    test('retrieveEvents returns list of events', () async {
      final now = DateTime.now();
      final later = now.add(Duration(days: 7));

      final events = await plugin.retrieveEvents(now, later, ['cal1']);

      expect(log.length, equals(1));
      expect(log[0].method, equals('retrieveEvents'));
      expect(log[0].arguments['startDate'], equals(now.millisecondsSinceEpoch));
      expect(log[0].arguments['endDate'], equals(later.millisecondsSinceEpoch));
      expect(log[0].arguments['calendarIds'], equals(['cal1']));

      expect(events, hasLength(1));
      expect(events[0]['eventId'], equals('event1'));
      expect(events[0]['title'], equals('Test Event'));
    });

    test('createEvent with all parameters', () async {
      final startDate = DateTime(2024, 3, 15, 14, 0);
      final endDate = DateTime(2024, 3, 15, 15, 0);

      final eventId = await plugin.createEvent(
        'cal-123',
        'Team Meeting',
        startDate,
        endDate,
        false,
        'Weekly sync',
        'Conference Room A',
        'America/New_York',
        'busy',
      );

      expect(log.length, equals(1));
      expect(log[0].method, equals('createEvent'));
      expect(log[0].arguments['calendarId'], equals('cal-123'));
      expect(log[0].arguments['title'], equals('Team Meeting'));
      expect(log[0].arguments['startDate'],
          equals(startDate.millisecondsSinceEpoch));
      expect(
          log[0].arguments['endDate'], equals(endDate.millisecondsSinceEpoch));
      expect(log[0].arguments['isAllDay'], equals(false));
      expect(log[0].arguments['description'], equals('Weekly sync'));
      expect(log[0].arguments['location'], equals('Conference Room A'));
      expect(log[0].arguments['timeZone'], equals('America/New_York'));
      expect(log[0].arguments['availability'], equals('busy'));
      expect(eventId, equals('android-event-id-789'));
    });

    test('createEvent with minimal parameters', () async {
      final startDate = DateTime(2024, 3, 15, 14, 0);
      final endDate = DateTime(2024, 3, 15, 15, 0);

      final eventId = await plugin.createEvent(
        'cal-123',
        'Quick Event',
        startDate,
        endDate,
        true,
        null,
        null,
        null,
        'free',
      );

      expect(log.length, equals(1));
      expect(log[0].method, equals('createEvent'));
      expect(log[0].arguments['calendarId'], equals('cal-123'));
      expect(log[0].arguments['title'], equals('Quick Event'));
      expect(log[0].arguments['isAllDay'], equals(true));
      expect(log[0].arguments['description'], isNull);
      expect(log[0].arguments['location'], isNull);
      expect(log[0].arguments['timeZone'], isNull);
      expect(log[0].arguments['availability'], equals('free'));
      expect(eventId, equals('android-event-id-789'));
    });

    test('deleteEvent calls method with correct arguments', () async {
      await plugin.deleteEvent('event-123', false);

      expect(log.length, equals(1));
      expect(log[0].method, equals('deleteEvent'));
      expect(log[0].arguments['instanceId'], equals('event-123'));
      expect(log[0].arguments['deleteAllInstances'], equals(false));
    });

    test('deleteEvent with deleteAllInstances true', () async {
      await plugin.deleteEvent('event-123@123456789', true);

      expect(log.length, equals(1));
      expect(log[0].method, equals('deleteEvent'));
      expect(log[0].arguments['instanceId'], equals('event-123@123456789'));
      expect(log[0].arguments['deleteAllInstances'], equals(true));
    });
  });
}
