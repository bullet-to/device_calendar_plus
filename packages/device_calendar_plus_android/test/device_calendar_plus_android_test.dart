import 'package:device_calendar_plus_android/device_calendar_plus_android.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceCalendarPlusAndroid', () {
    late DeviceCalendarPlusAndroid plugin;
    late List<MethodCall> log;

    setUp(() async {
      plugin = DeviceCalendarPlusAndroid();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin.methodChannel, (methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
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
          case 'listEvents':
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
          case 'updateEvent':
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

    test('createCalendar with custom account name', () async {
      final calendarId = await plugin.createCalendar(
        'My App Calendar',
        null,
        CreateCalendarOptionsAndroid(accountName: 'MyApp'),
      );

      expect(log.length, equals(1));
      expect(log[0].method, equals('createCalendar'));
      expect(log[0].arguments['name'], equals('My App Calendar'));
      expect(log[0].arguments['accountName'], equals('MyApp'));
      expect(calendarId, equals('android-calendar-id-456'));
    });

    test('listEvents serializes dates and calendarIds correctly', () async {
      final now = DateTime.now();
      final later = now.add(Duration(days: 7));

      await plugin.listEvents(now, later, ['cal1']);

      expect(log[0].arguments['startDate'], equals(now.millisecondsSinceEpoch));
      expect(log[0].arguments['endDate'], equals(later.millisecondsSinceEpoch));
      expect(log[0].arguments['calendarIds'], equals(['cal1']));
    });

    test('createEvent serializes all arguments correctly', () async {
      final startDate = DateTime(2024, 3, 15, 14, 0);
      final endDate = DateTime(2024, 3, 15, 15, 0);

      await plugin.createEvent(
        'cal-123',
        'Team Meeting',
        startDate,
        endDate,
        false,
        'Weekly sync',
        'Conference Room A',
        'America/New_York',
        'busy',
        null,
      );

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
    });

<<<<<<< HEAD
    test('updateEvent serializes only provided fields', () async {
=======
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
      await plugin.deleteEvent('event-123');

      expect(log.length, equals(1));
      expect(log[0].method, equals('deleteEvent'));
      expect(log[0].arguments['instanceId'], equals('event-123'));
    });

    test('deleteEvent for recurring event deletes entire series', () async {
      await plugin.deleteEvent('event-123@123456789');

      expect(log.length, equals(1));
      expect(log[0].method, equals('deleteEvent'));
      expect(log[0].arguments['instanceId'], equals('event-123@123456789'));
    });

    test('updateEvent with all parameters', () async {
      final startDate = DateTime(2024, 3, 20, 10, 0);
      final endDate = DateTime(2024, 3, 20, 11, 0);

      await plugin.updateEvent(
        'event-123',
        title: 'Updated Title',
        startDate: startDate,
        endDate: endDate,
        description: 'Updated description',
        location: 'Updated location',
        isAllDay: false,
        timeZone: 'America/New_York',
        availability: 'free',
      );

      expect(log.length, equals(1));
      expect(log[0].method, equals('updateEvent'));
      expect(log[0].arguments['instanceId'], equals('event-123'));
      expect(log[0].arguments['title'], equals('Updated Title'));
      expect(log[0].arguments['startDate'],
          equals(startDate.millisecondsSinceEpoch));
      expect(
          log[0].arguments['endDate'], equals(endDate.millisecondsSinceEpoch));
      expect(log[0].arguments['description'], equals('Updated description'));
      expect(log[0].arguments['location'], equals('Updated location'));
      expect(log[0].arguments['isAllDay'], equals(false));
      expect(log[0].arguments['timeZone'], equals('America/New_York'));
      expect(log[0].arguments['availability'], equals('free'));
    });

    test('updateEvent with minimal parameters', () async {
>>>>>>> f27a039... Fix availability persistence across platforms
      await plugin.updateEvent(
        'event-123',
        title: 'New Title',
      );

      expect(log[0].arguments['eventId'], equals('event-123'));
      expect(log[0].arguments['title'], equals('New Title'));
      expect(log[0].arguments['startDate'], isNull);
      expect(log[0].arguments['endDate'], isNull);
      expect(log[0].arguments['description'], isNull);
      expect(log[0].arguments['location'], isNull);
      expect(log[0].arguments['isAllDay'], isNull);
      expect(log[0].arguments['timeZone'], isNull);
      expect(log[0].arguments['availability'], isNull);
    });
  });
}
