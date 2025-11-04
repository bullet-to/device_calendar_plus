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

  // Callback to capture createEvent arguments
  Future<String> Function(
    String calendarId,
    String title,
    DateTime startDate,
    DateTime endDate,
    bool isAllDay,
    String? description,
    String? location,
    String? timeZone,
    String availability,
  )? _createEventCallback;

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

  void setCreateEventCallback(
    Future<String> Function(
      String calendarId,
      String title,
      DateTime startDate,
      DateTime endDate,
      bool isAllDay,
      String? description,
      String? location,
      String? timeZone,
      String availability,
    ) callback,
  ) {
    _createEventCallback = callback;
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
  Future<String> createCalendar(String name, String? colorHex) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return 'mock-calendar-id-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> updateCalendar(
      String calendarId, String? name, String? colorHex) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
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
  Future<void> showEvent(String instanceId) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    // Mock implementation does nothing
  }

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
  ) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }

    // Use callback if set, otherwise return default
    if (_createEventCallback != null) {
      return _createEventCallback!(
        calendarId,
        title,
        startDate,
        endDate,
        isAllDay,
        description,
        location,
        timeZone,
        availability,
      );
    }

    return 'mock-event-id-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> deleteEvent(String instanceId, bool deleteAllInstances) async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
  }
}

void main() {
  late MockDeviceCalendarPlusPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mockPlatform;
  });

  group('DeviceCalendar', () {
    group('getPlatformVersion', () {
      test('returns platform version from platform interface', () async {
        mockPlatform.setPlatformVersion('Test Platform 1.0');
        final result = await DeviceCalendar.instance.getPlatformVersion();
        expect(result, 'Test Platform 1.0');
      });
    });

    group('requestPermissions', () {
      group('status conversion', () {
        test('converts status code to CalendarPermissionStatus', () async {
          mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);
          final result = await DeviceCalendar.instance.requestPermissions();
          expect(result, CalendarPermissionStatus.granted);
        });
      });

      group('edge case handling', () {
        test('defaults to denied when status is null', () async {
          mockPlatform._permissionStatusCode = null;
          final result = await DeviceCalendar.instance.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });

        test('defaults to denied when status is negative', () async {
          mockPlatform._permissionStatusCode = -1;
          final result = await DeviceCalendar.instance.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });

        test('defaults to denied when status is out of range', () async {
          mockPlatform._permissionStatusCode = 999;
          final result = await DeviceCalendar.instance.requestPermissions();
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
            () => DeviceCalendar.instance.requestPermissions(),
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
            () => DeviceCalendar.instance.requestPermissions(),
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

        final calendars = await DeviceCalendar.instance.listCalendars();

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
          () => DeviceCalendar.instance.listCalendars(),
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
        final calendars = await DeviceCalendar.instance.listCalendars();
        expect(calendars, isEmpty);
      });
    });

    group('createCalendar', () {
      test('returns calendar ID when created successfully', () async {
        final calendarId =
            await DeviceCalendar.instance.createCalendar(name: 'Test Calendar');

        expect(calendarId, isNotEmpty);
        expect(calendarId, isA<String>());
        expect(calendarId, startsWith('mock-calendar-id'));
      });

      test('creates calendar with name only', () async {
        final calendarId =
            await DeviceCalendar.instance.createCalendar(name: 'Work Calendar');

        expect(calendarId, isNotEmpty);
      });

      test('creates calendar with name and color', () async {
        final calendarId = await DeviceCalendar.instance.createCalendar(
          name: 'Personal Calendar',
          colorHex: '#FF5733',
        );

        expect(calendarId, isNotEmpty);
      });

      test('throws DeviceCalendarException when permission denied', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendar.instance.createCalendar(name: 'Test Calendar'),
          throwsA(
            isA<DeviceCalendarException>().having(
              (e) => e.errorCode,
              'errorCode',
              DeviceCalendarError.permissionDenied,
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
          () => DeviceCalendar.instance.createCalendar(name: 'Test Calendar'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'SOME_OTHER_ERROR',
            ),
          ),
        );
      });

      test('throws ArgumentError when name is empty', () async {
        expect(
          () => DeviceCalendar.instance.createCalendar(name: ''),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('cannot be empty'),
            ),
          ),
        );
      });

      test('throws ArgumentError when name is whitespace only', () async {
        expect(
          () => DeviceCalendar.instance.createCalendar(name: '   '),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('cannot be empty'),
            ),
          ),
        );
      });
    });

    group('updateCalendar', () {
      test('updates calendar successfully', () async {
        await DeviceCalendar.instance.updateCalendar(
          'calendar-123',
          name: 'Updated Name',
          colorHex: '#00FF00',
        );
        // Should complete without error
      });

      test('updates calendar with name only', () async {
        await DeviceCalendar.instance.updateCalendar(
          'calendar-123',
          name: 'New Name',
        );
        // Should complete without error
      });

      test('updates calendar with color only', () async {
        await DeviceCalendar.instance.updateCalendar(
          'calendar-123',
          colorHex: '#FF5733',
        );
        // Should complete without error
      });

      test('throws ArgumentError when no parameters provided', () async {
        expect(
          () => DeviceCalendar.instance.updateCalendar('calendar-123'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('At least one'),
            ),
          ),
        );
      });

      test('throws ArgumentError when name is empty', () async {
        expect(
          () =>
              DeviceCalendar.instance.updateCalendar('calendar-123', name: ''),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('cannot be empty'),
            ),
          ),
        );
      });

      test('throws ArgumentError when name is whitespace only', () async {
        expect(
          () => DeviceCalendar.instance
              .updateCalendar('calendar-123', name: '   '),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('cannot be empty'),
            ),
          ),
        );
      });

      test('converts permissionDenied PlatformException', () async {
        mockPlatform.throwException(
          PlatformException(
              code: 'PERMISSION_DENIED', message: 'Permission denied'),
        );

        expect(
          () => DeviceCalendar.instance
              .updateCalendar('calendar-123', name: 'New Name'),
          throwsA(
            isA<DeviceCalendarException>().having(
              (e) => e.errorCode,
              'errorCode',
              DeviceCalendarError.permissionDenied,
            ),
          ),
        );

        mockPlatform.clearException();
      });

      test('rethrows unknown PlatformException', () async {
        mockPlatform.throwException(
          PlatformException(code: 'someOtherError', message: 'Some error'),
        );

        expect(
          () => DeviceCalendar.instance
              .updateCalendar('calendar-123', name: 'New Name'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'someOtherError',
            ),
          ),
        );

        mockPlatform.clearException();
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

        final events = await DeviceCalendar.instance.retrieveEvents(
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

        final events = await DeviceCalendar.instance.retrieveEvents(
          now,
          now.add(Duration(days: 1)),
        );

        expect(events, hasLength(1));
        expect(events[0].availability, EventAvailability.notSupported);
        expect(events[0].status, EventStatus.none);
      });

      test('returns empty list when no events', () async {
        mockPlatform.setEvents([]);
        final events = await DeviceCalendar.instance.retrieveEvents(
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
          () => DeviceCalendar.instance.retrieveEvents(
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

        final event = await DeviceCalendar.instance.getEvent('event1');

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

        final event = await DeviceCalendar.instance.getEvent(instanceId);

        expect(event, isNotNull);
        expect(event!.eventId, 'recurring1');
        expect(event.instanceId, instanceId);
        expect(event.title, 'Daily Standup');
        expect(event.startDate, eventStart);
      });

      test('returns null when event not found', () async {
        mockPlatform.setEvent(null);

        final event = await DeviceCalendar.instance.getEvent('nonexistent');

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

        final event = await DeviceCalendar.instance.getEvent(instanceId);

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
          () => DeviceCalendar.instance.getEvent('event1'),
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

    group('createEvent', () {
      test('creates event with all parameters', () async {
        final calendarId = 'cal-123';
        final title = 'Team Meeting';
        final startDate = DateTime(2024, 3, 15, 14, 0);
        final endDate = DateTime(2024, 3, 15, 15, 0);

        final eventId = await DeviceCalendar.instance.createEvent(
          calendarId: calendarId,
          title: title,
          startDate: startDate,
          endDate: endDate,
          description: 'Weekly sync',
          location: 'Conference Room A',
          timeZone: 'America/New_York',
          availability: EventAvailability.busy,
        );

        expect(eventId, isNotEmpty);
        expect(eventId, startsWith('mock-event-id-'));
      });

      test('creates all-day event', () async {
        final eventId = await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'All Day Event',
          startDate: DateTime(2024, 3, 15),
          endDate: DateTime(2024, 3, 16),
          isAllDay: true,
          availability: EventAvailability.free,
        );

        expect(eventId, isNotEmpty);
      });

      test('normalizes dates for all-day events (strips time components)',
          () async {
        // Create an all-day event with time components
        final startWithTime = DateTime(2024, 3, 15, 14, 30, 45);
        final endWithTime = DateTime(2024, 3, 16, 18, 15, 30);

        // Mock to capture what was actually passed to the platform
        DateTime? capturedStart;
        DateTime? capturedEnd;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setCreateEventCallback((
          calendarId,
          title,
          startDate,
          endDate,
          isAllDay,
          description,
          location,
          timeZone,
          availability,
        ) {
          capturedStart = startDate;
          capturedEnd = endDate;
          return Future.value('event-id');
        });

        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'All Day Event',
          startDate: startWithTime,
          endDate: endWithTime,
          isAllDay: true,
        );

        // Verify dates were normalized to midnight
        expect(capturedStart, isNotNull);
        expect(capturedEnd, isNotNull);
        expect(capturedStart!.hour, 0);
        expect(capturedStart!.minute, 0);
        expect(capturedStart!.second, 0);
        expect(capturedStart!.millisecond, 0);
        expect(capturedEnd!.hour, 0);
        expect(capturedEnd!.minute, 0);
        expect(capturedEnd!.second, 0);
        expect(capturedEnd!.millisecond, 0);

        // Verify dates preserved the day
        expect(capturedStart!.year, 2024);
        expect(capturedStart!.month, 3);
        expect(capturedStart!.day, 15);
        expect(capturedEnd!.year, 2024);
        expect(capturedEnd!.month, 3);
        expect(capturedEnd!.day, 16);
      });

      test('preserves exact time for non-all-day events', () async {
        final startWithTime = DateTime(2024, 3, 15, 14, 30, 45);
        final endWithTime = DateTime(2024, 3, 15, 18, 15, 30);

        DateTime? capturedStart;
        DateTime? capturedEnd;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setCreateEventCallback((
          calendarId,
          title,
          startDate,
          endDate,
          isAllDay,
          description,
          location,
          timeZone,
          availability,
        ) {
          capturedStart = startDate;
          capturedEnd = endDate;
          return Future.value('event-id');
        });

        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'Meeting',
          startDate: startWithTime,
          endDate: endWithTime,
          isAllDay: false,
        );

        // Verify exact times were preserved
        expect(capturedStart, equals(startWithTime));
        expect(capturedEnd, equals(endWithTime));
      });

      test('creates event with minimal parameters', () async {
        final eventId = await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'Quick Meeting',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(hours: 1)),
        );

        expect(eventId, isNotEmpty);
      });

      test('throws ArgumentError when calendar ID is empty', () async {
        expect(
          () => DeviceCalendar.instance.createEvent(
            calendarId: '',
            title: 'Meeting',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(Duration(hours: 1)),
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when title is empty', () async {
        expect(
          () => DeviceCalendar.instance.createEvent(
            calendarId: 'cal-123',
            title: '',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(Duration(hours: 1)),
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when end date is before start date', () async {
        final now = DateTime.now();
        expect(
          () => DeviceCalendar.instance.createEvent(
            calendarId: 'cal-123',
            title: 'Invalid Event',
            startDate: now,
            endDate: now.subtract(Duration(hours: 1)),
          ),
          throwsArgumentError,
        );
      });

      test('converts PlatformException to DeviceCalendarException', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendar.instance.createEvent(
            calendarId: 'cal-123',
            title: 'Meeting',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(Duration(hours: 1)),
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

    group('deleteEvent', () {
      test('deletes single event', () async {
        await DeviceCalendar.instance.deleteEvent('event-123');
        // Should complete without error
      });

      test('deletes all instances of recurring event', () async {
        await DeviceCalendar.instance.deleteEvent(
          'event-123@123456789',
          deleteAllInstances: true,
        );
        // Should complete without error
      });

      test('deletes single instance of recurring event', () async {
        await DeviceCalendar.instance.deleteEvent(
          'event-123@123456789',
          deleteAllInstances: false,
        );
        // Should complete without error
      });

      test('throws ArgumentError when instance ID is empty', () async {
        expect(
          () => DeviceCalendar.instance.deleteEvent(''),
          throwsArgumentError,
        );
      });

      test('converts PlatformException to DeviceCalendarException', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendar.instance.deleteEvent('event-123'),
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
