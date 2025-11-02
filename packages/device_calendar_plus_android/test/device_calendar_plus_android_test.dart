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
  });
}
