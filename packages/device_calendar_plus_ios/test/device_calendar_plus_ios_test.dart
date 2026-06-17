import 'package:device_calendar_plus_ios/device_calendar_plus_ios.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceCalendarPlusIos', () {
    late DeviceCalendarPlusIos plugin;
    late List<MethodCall> log;

    setUp(() async {
      plugin = DeviceCalendarPlusIos();

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
            return 'test-calendar-id-123';
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
            return 'ios-event-id-456';
          case 'updateEvent':
            return null;
          default:
            return null;
        }
      });
    });

    test('can be registered', () {
      DeviceCalendarPlusIos.registerWith();
      expect(DeviceCalendarPlusPlatform.instance, isA<DeviceCalendarPlusIos>());
    });

    test('requestPermissions serializes the access level', () async {
      await plugin.requestPermissions(true);

      expect(log[0].method, equals('requestPermissions'));
      expect(log[0].arguments['writeOnly'], isTrue);
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
        'https://example.com/event/123',
        'America/New_York',
        'busy',
        null,
        [15, 60],
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
      expect(log[0].arguments['url'], equals('https://example.com/event/123'));
      expect(log[0].arguments['timeZone'], equals('America/New_York'));
      expect(log[0].arguments['availability'], equals('busy'));
      expect(log[0].arguments['reminders'], equals([15, 60]));
    });

    test('updateEvent serializes only provided fields', () async {
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
      // Reminders unchanged: no key, not in clearedFields.
      expect(log[0].arguments['reminders'], isNull);
      expect(log[0].arguments['clearedFields'], isEmpty);
    });

    test('updateEvent serializes a reminders Patch.set as minutes', () async {
      await plugin.updateEvent(
        'event-123',
        reminders: Patch.set([30, 60]),
      );

      expect(log[0].arguments['reminders'], equals([30, 60]));
      expect(log[0].arguments['clearedFields'], isEmpty);
    });

    test('updateEvent serializes a reminders Patch.clear via clearedFields',
        () async {
      await plugin.updateEvent(
        'event-123',
        reminders: const Patch.clear(),
      );

      expect(log[0].arguments['reminders'], isNull);
      expect(log[0].arguments['clearedFields'], contains('reminders'));
    });
  });
}
