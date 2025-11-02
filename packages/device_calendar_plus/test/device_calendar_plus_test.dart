import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  String? _platformVersion;
  int? _permissionStatusCode = 4; // CalendarPermissionStatus.notDetermined
  List<Map<String, dynamic>> _calendars = [];
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _event;
  PlatformException? _exceptionToThrow;

  void setPlatformVersion(String? version) {
    _platformVersion = version;
  }

  void setPermissionStatus(CalendarPermissionStatus status) {
    _permissionStatusCode = status.index;
  }

  void setCalendars(List<Map<String, dynamic>> calendars) {
    _calendars = calendars;
  }

  void setEvents(List<Map<String, dynamic>> events) {
    _events = events;
  }

  void setEvent(Map<String, dynamic>? event) {
    _event = event;
  }

  void throwException(PlatformException exception) {
    _exceptionToThrow = exception;
  }

  void clearException() {
    _exceptionToThrow = null;
  }

  @override
  Future<String?> getPlatformVersion() async => _platformVersion;

  @override
  Future<int?> requestPermissions() async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return _permissionStatusCode;
  }

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return _calendars;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return _events;
  }

  @override
  Future<Map<String, dynamic>?> getEvent(String instanceId) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return _event;
  }

  @override
  Future<void> openEvent(String instanceId, bool useModal) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    // Mock implementation does nothing
  }
}

void main() {
  late MockDeviceCalendarPlusPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mockPlatform;
  });

  group('DeviceCalendarPlugin', () {
    group('getPlatformVersion', () {
      test('returns platform version from platform interface', () async {
        mockPlatform.setPlatformVersion('Test Platform 1.0');
        final result = await DeviceCalendarPlugin.getPlatformVersion();
        expect(result, 'Test Platform 1.0');
      });
    });

    group('requestPermissions', () {
      group('status conversion', () {
        test('converts status code to CalendarPermissionStatus', () async {
          mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.granted);
        });
      });

      group('edge case handling', () {
        test('defaults to denied when status is null', () async {
          mockPlatform._permissionStatusCode = null;
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });

        test('defaults to denied when status is negative', () async {
          mockPlatform._permissionStatusCode = -1;
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });

        test('defaults to denied when status is out of range', () async {
          mockPlatform._permissionStatusCode = 999;
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });
      });

      group('error handling', () {
        test('throws DeviceCalendarException when permissions not declared',
            () async {
          mockPlatform.throwException(
            PlatformException(
              code: 'PERMISSIONS_NOT_DECLARED',
              message: 'Calendar permissions must be declared',
            ),
          );

          expect(
            () => DeviceCalendarPlugin.requestPermissions(),
            throwsA(
              isA<DeviceCalendarException>().having(
                (e) => e.errorCode,
                'errorCode',
                DeviceCalendarError.permissionsNotDeclared,
              ),
            ),
          );
        });

        test('rethrows other PlatformExceptions unchanged', () async {
          mockPlatform.throwException(
            PlatformException(
              code: 'SOME_OTHER_ERROR',
              message: 'Something went wrong',
            ),
          );

          expect(
            () => DeviceCalendarPlugin.requestPermissions(),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'SOME_OTHER_ERROR',
              ),
            ),
          );
        });
      });
    });

    group('listCalendars', () {
      test('returns list of Calendar objects', () async {
        mockPlatform.setCalendars([
          {
            'id': '1',
            'name': 'Work',
            'colorHex': '#FF0000',
            'readOnly': false,
            'accountName': 'work@example.com',
            'accountType': 'com.google',
            'isPrimary': true,
            'hidden': false,
          },
          {
            'id': '2',
            'name': 'Personal',
            'readOnly': true,
            'isPrimary': false,
            'hidden': false,
          },
        ]);

        final calendars = await DeviceCalendarPlugin.listCalendars();

        expect(calendars, hasLength(2));
        expect(calendars[0].id, '1');
        expect(calendars[0].name, 'Work');
        expect(calendars[0].colorHex, '#FF0000');
        expect(calendars[0].readOnly, false);
        expect(calendars[0].isPrimary, true);
        expect(calendars[0].hidden, false);

        expect(calendars[1].id, '2');
        expect(calendars[1].name, 'Personal');
        expect(calendars[1].readOnly, true);
        expect(calendars[1].isPrimary, false);
      });

      test('throws DeviceCalendarException when permission denied', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendarPlugin.listCalendars(),
          throwsA(
            isA<DeviceCalendarException>().having(
              (e) => e.errorCode,
              'errorCode',
              DeviceCalendarError.permissionDenied,
            ),
          ),
        );
      });

      test('returns empty list when no calendars', () async {
        mockPlatform.setCalendars([]);
        final calendars = await DeviceCalendarPlugin.listCalendars();
        expect(calendars, isEmpty);
      });
    });

    group('retrieveEvents', () {
      test('returns list of Event objects', () async {
        final now = DateTime.now();
        final later = now.add(Duration(hours: 2));

        mockPlatform.setEvents([
          {
            'eventId': 'event1',
            'instanceId': 'event1',
            'calendarId': 'cal1',
            'title': 'Team Meeting',
            'description': 'Weekly sync',
            'location': 'Conference Room A',
            'startDate': now.millisecondsSinceEpoch,
            'endDate': later.millisecondsSinceEpoch,
            'isAllDay': false,
            'availability': 'busy',
            'status': 'confirmed',
            'isRecurring': false,
          },
          {
            'eventId': 'event2',
            'instanceId': 'event2',
            'calendarId': 'cal1',
            'title': 'All Day Event',
            'startDate': now.millisecondsSinceEpoch,
            'endDate': later.millisecondsSinceEpoch,
            'isAllDay': true,
            'availability': 'free',
            'status': 'tentative',
            'isRecurring': false,
          },
        ]);

        final events = await DeviceCalendarPlugin.retrieveEvents(
          now,
          now.add(Duration(days: 7)),
        );

        expect(events, hasLength(2));
        expect(events[0].eventId, 'event1');
        expect(events[0].title, 'Team Meeting');
        expect(events[0].description, 'Weekly sync');
        expect(events[0].location, 'Conference Room A');
        expect(events[0].isAllDay, false);
        expect(events[0].availability, EventAvailability.busy);
        expect(events[0].status, EventStatus.confirmed);

        expect(events[1].eventId, 'event2');
        expect(events[1].title, 'All Day Event');
        expect(events[1].isAllDay, true);
        expect(events[1].availability, EventAvailability.free);
        expect(events[1].status, EventStatus.tentative);
      });

      test('handles unknown availability and status gracefully', () async {
        final now = DateTime.now();

        mockPlatform.setEvents([
          {
            'eventId': 'event1',
            'instanceId': 'event1',
            'calendarId': 'cal1',
            'title': 'Test Event',
            'startDate': now.millisecondsSinceEpoch,
            'endDate': now.millisecondsSinceEpoch,
            'isAllDay': false,
            'availability': 'unknownValue',
            'status': 'unknownStatus',
            'isRecurring': false,
          },
        ]);

        final events = await DeviceCalendarPlugin.retrieveEvents(
          now,
          now.add(Duration(days: 1)),
        );

        expect(events, hasLength(1));
        expect(events[0].availability, EventAvailability.notSupported);
        expect(events[0].status, EventStatus.none);
      });

      test('returns empty list when no events', () async {
        mockPlatform.setEvents([]);
        final events = await DeviceCalendarPlugin.retrieveEvents(
          DateTime.now(),
          DateTime.now().add(Duration(days: 7)),
        );
        expect(events, isEmpty);
      });

      test('throws DeviceCalendarException when permission denied', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendarPlugin.retrieveEvents(
            DateTime.now(),
            DateTime.now().add(Duration(days: 7)),
          ),
          throwsA(
            isA<DeviceCalendarException>().having(
              (e) => e.errorCode,
              'errorCode',
              DeviceCalendarError.permissionDenied,
            ),
          ),
        );
      });
    });

    group('getEvent', () {
      test('returns non-recurring event when found by instanceId', () async {
        final now = DateTime.now();

        mockPlatform.setEvent({
          'eventId': 'event1',
          'instanceId': 'event1',
          'calendarId': 'cal1',
          'title': 'Team Meeting',
          'description': 'Weekly sync',
          'startDate': now.millisecondsSinceEpoch,
          'endDate': now.add(Duration(hours: 1)).millisecondsSinceEpoch,
          'isAllDay': false,
          'availability': 'busy',
          'status': 'confirmed',
          'isRecurring': false,
        });

        final event = await DeviceCalendarPlugin.getEvent('event1');

        expect(event, isNotNull);
        expect(event!.eventId, 'event1');
        expect(
            event.instanceId, 'event1'); // Non-recurring: instanceId == eventId
        expect(event.title, 'Team Meeting');
        expect(event.description, 'Weekly sync');
      });

      test('returns recurring event instance by instanceId', () async {
        final eventStart = DateTime(2025, 11, 15, 14, 0);
        final instanceId = 'recurring1@${eventStart.millisecondsSinceEpoch}';

        mockPlatform.setEvent({
          'eventId': 'recurring1',
          'instanceId': instanceId,
          'calendarId': 'cal1',
          'title': 'Daily Standup',
          'startDate': eventStart.millisecondsSinceEpoch,
          'endDate':
              eventStart.add(Duration(minutes: 30)).millisecondsSinceEpoch,
          'isAllDay': false,
          'availability': 'busy',
          'status': 'confirmed',
          'isRecurring': true,
        });

        final event = await DeviceCalendarPlugin.getEvent(instanceId);

        expect(event, isNotNull);
        expect(event!.eventId, 'recurring1');
        expect(event.instanceId, instanceId);
        expect(event.title, 'Daily Standup');
        expect(event.startDate, eventStart);
      });

      test('returns null when event not found', () async {
        mockPlatform.setEvent(null);

        final event = await DeviceCalendarPlugin.getEvent('nonexistent');

        expect(event, isNull);
      });

      test('parses instanceId correctly for recurring events', () async {
        final eventStart = DateTime(2025, 11, 15, 14, 0);
        final instanceId = 'event123@${eventStart.millisecondsSinceEpoch}';

        mockPlatform.setEvent({
          'eventId': 'event123',
          'instanceId': instanceId,
          'calendarId': 'cal1',
          'title': 'Recurring Event',
          'startDate': eventStart.millisecondsSinceEpoch,
          'endDate': eventStart.add(Duration(hours: 1)).millisecondsSinceEpoch,
          'isAllDay': false,
          'availability': 'busy',
          'status': 'confirmed',
          'isRecurring': true,
        });

        final event = await DeviceCalendarPlugin.getEvent(instanceId);

        expect(event, isNotNull);
        expect(event!.eventId, 'event123');
        expect(event.startDate, eventStart);
      });

      test('throws DeviceCalendarException when permission denied', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendarPlugin.getEvent('event1'),
          throwsA(
            isA<DeviceCalendarException>().having(
              (e) => e.errorCode,
              'errorCode',
              DeviceCalendarError.permissionDenied,
            ),
          ),
        );
      });
    });
  });
}
