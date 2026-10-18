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
          case 'updateRecurring':
            return 'android-event-id-789';
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
        android: const CalendarOptionsAndroid(accountName: 'MyApp'),
        ios: const CalendarOptionsIos(sourceId: 'ignored'),
      );

      expect(log.length, equals(1));
      expect(log[0].method, equals('createCalendar'));
      expect(log[0].arguments['name'], equals('My App Calendar'));
      expect(log[0].arguments['accountName'], equals('MyApp'));
      expect(log[0].arguments.containsKey('sourceId'), isFalse);
      expect(calendarId, equals('android-calendar-id-456'));
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

    group('android status', () {
      test('createEvent sends the status by name', () async {
        await plugin.createEvent(
          null,
          'Title',
          DateTime(2024, 3, 15, 14),
          DateTime(2024, 3, 15, 15),
          false,
          null,
          null,
          null,
          null,
          'busy',
          null,
          null,
          android: const EventOptionsAndroid(
            status: EventStatusAndroid.tentative,
          ),
        );

        expect(log.single.arguments['status'], 'tentative');
      });

      test('createEvent without android options sends no status', () async {
        await plugin.createEvent(
          null,
          'Title',
          DateTime(2024, 3, 15, 14),
          DateTime(2024, 3, 15, 15),
          false,
          null,
          null,
          null,
          null,
          'busy',
          null,
          null,
        );

        expect(log.single.arguments['status'], isNull);
      });

      test('updateEvent sends the status by name', () async {
        await plugin.updateEvent(
          'event-123',
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.canceled,
          ),
        );

        expect(log.single.arguments['status'], 'canceled');
      });

      test('updateEvent without a status sends none', () async {
        await plugin.updateEvent(
          'event-123',
          title: 'New Title',
          android: const EventUpdateOptionsAndroid(),
        );

        expect(log.single.arguments['status'], isNull);
      });

      test('updateRecurring sends the status by name', () async {
        await plugin.updateRecurring(
          'event-123',
          1000,
          'thisAndFollowing',
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.confirmed,
          ),
        );

        expect(log.single.arguments['status'], 'confirmed');
      });
    });
  });
}
