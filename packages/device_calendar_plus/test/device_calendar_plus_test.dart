import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  String? _permissionStatusCode = "notDetermined";
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
    String? recurrenceRule,
  )? _createEventCallback;

  // Callback to capture updateEvent arguments
  Future<void> Function(
    String eventId, {
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
    String? availability,
  })? _updateEventCallback;

  void setPermissionStatus(CalendarPermissionStatus status) {
    _permissionStatusCode = status.name;
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
      String? recurrenceRule,
    ) callback,
  ) {
    _createEventCallback = callback;
  }

  void setUpdateEventCallback(
    Future<void> Function(
      String eventId, {
      String? title,
      DateTime? startDate,
      DateTime? endDate,
      String? description,
      String? location,
      bool? isAllDay,
      String? timeZone,
      String? availability,
    }) callback,
  ) {
    _updateEventCallback = callback;
  }

  @override
  Future<String?> requestPermissions() async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return _permissionStatusCode;
  }

  @override
  Future<String?> hasPermissions() async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return _permissionStatusCode;
  }

  @override
  Future<void> openAppSettings() async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
  }

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> listSources() async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return [];
  }

  @override
  Future<String> createCalendar(
    String name,
    String? colorHex,
    CreateCalendarPlatformOptions? platformOptions,
  ) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return 'mock-calendar-id';
  }

  @override
  Future<void> updateCalendar(
      String calendarId, String? name, String? colorHex) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
  }

  @override
  Future<List<Map<String, dynamic>>> listEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return _events;
  }

  @override
  Future<Map<String, dynamic>?> getEvent(String eventId, int? timestamp) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return _event;
  }

  @override
  Future<void> showEventModal(String eventId, int? timestamp) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
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
    String? recurrenceRule,
  ) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
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
        recurrenceRule,
      );
    }
    return 'mock-event-id';
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
  }

  @override
  Future<void> updateEvent(
    String eventId, {
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
  }) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    if (_updateEventCallback != null) {
      return _updateEventCallback!(
        eventId,
        title: title,
        startDate: startDate,
        endDate: endDate,
        description: description,
        location: location,
        isAllDay: isAllDay,
        timeZone: timeZone,
      );
    }
  }

  // Callback to capture showCreateEventModal arguments
  Future<void> Function({
    String? title,
    int? startDate,
    int? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? recurrenceRule,
    String? availability,
  })? _showCreateEventModalCallback;

  void setShowCreateEventModalCallback(
    Future<void> Function({
      String? title,
      int? startDate,
      int? endDate,
      String? description,
      String? location,
      bool? isAllDay,
      String? recurrenceRule,
      String? availability,
    }) callback,
  ) {
    _showCreateEventModalCallback = callback;
  }

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
  }) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    if (_showCreateEventModalCallback != null) {
      return _showCreateEventModalCallback!(
        title: title,
        startDate: startDate,
        endDate: endDate,
        description: description,
        location: location,
        isAllDay: isAllDay,
        recurrenceRule: recurrenceRule,
        availability: availability,
      );
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
    group('requestPermissions', () {
      test('converts status code to CalendarPermissionStatus', () async {
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);
        final result = await DeviceCalendar.instance.requestPermissions();
        expect(result, CalendarPermissionStatus.granted);
      });

      test('defaults to denied when status is null', () async {
        mockPlatform._permissionStatusCode = null;
        final result = await DeviceCalendar.instance.requestPermissions();
        expect(result, CalendarPermissionStatus.denied);
      });

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

    group('hasPermissions', () {
      test('defaults to denied when status is null', () async {
        mockPlatform._permissionStatusCode = null;
        final result = await DeviceCalendar.instance.hasPermissions();
        expect(result, CalendarPermissionStatus.denied);
      });
    });

    group('listEvents', () {
      test('parses event map into Event objects', () async {
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
        ]);

        final events = await DeviceCalendar.instance.listEvents(
          now,
          now.add(Duration(days: 7)),
        );

        expect(events, hasLength(1));
        expect(events[0].eventId, 'event1');
        expect(events[0].title, 'Team Meeting');
        expect(events[0].description, 'Weekly sync');
        expect(events[0].location, 'Conference Room A');
        expect(events[0].isAllDay, false);
        expect(events[0].availability, EventAvailability.busy);
        expect(events[0].status, EventStatus.confirmed);
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

        final events = await DeviceCalendar.instance.listEvents(
          now,
          now.add(Duration(days: 1)),
        );

        expect(events[0].availability, EventAvailability.notSupported);
        expect(events[0].status, EventStatus.none);
      });
    });

    group('getEvent', () {
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
        expect(event.startDate, eventStart);
      });

      test('returns null when event not found', () async {
        mockPlatform.setEvent(null);
        final event = await DeviceCalendar.instance.getEvent('nonexistent');
        expect(event, isNull);
      });
    });

    group('createEvent', () {
      test('normalizes dates for all-day events (strips time components)',
          () async {
        final startWithTime = DateTime(2024, 3, 15, 14, 30, 45);
        final endWithTime = DateTime(2024, 3, 16, 18, 15, 30);

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
          recurrenceRule,
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

        expect(capturedStart!.hour, 0);
        expect(capturedStart!.minute, 0);
        expect(capturedStart!.second, 0);
        expect(capturedStart!.millisecond, 0);
        expect(capturedEnd!.hour, 0);
        expect(capturedEnd!.minute, 0);
        expect(capturedEnd!.second, 0);
        expect(capturedEnd!.millisecond, 0);

        expect(capturedStart!.day, 15);
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
          recurrenceRule,
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
        );

        expect(capturedStart, equals(startWithTime));
        expect(capturedEnd, equals(endWithTime));
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

      test('converts PERMISSION_DENIED to DeviceCalendarException', () async {
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

    group('createCalendar', () {
      test('throws ArgumentError when name is empty', () async {
        expect(
          () => DeviceCalendar.instance.createCalendar(name: ''),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when name is whitespace only', () async {
        expect(
          () => DeviceCalendar.instance.createCalendar(name: '   '),
          throwsArgumentError,
        );
      });
    });

    group('updateCalendar', () {
      test('throws ArgumentError when no parameters provided', () async {
        expect(
          () => DeviceCalendar.instance.updateCalendar('calendar-123'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when name is empty', () async {
        expect(
          () =>
              DeviceCalendar.instance.updateCalendar('calendar-123', name: ''),
          throwsArgumentError,
        );
      });
    });

    group('updateEvent', () {
      test('normalizes dates when isAllDay is true', () async {
        final startWithTime = DateTime(2024, 3, 15, 14, 30, 45);
        final endWithTime = DateTime(2024, 3, 16, 18, 15, 30);

        DateTime? capturedStart;
        DateTime? capturedEnd;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setUpdateEventCallback((
          instanceId, {
          title,
          startDate,
          endDate,
          description,
          location,
          isAllDay,
          timeZone,
          availability,
        }) {
          capturedStart = startDate;
          capturedEnd = endDate;
          return Future.value();
        });
        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123',
          startDate: startWithTime,
          endDate: endWithTime,
          isAllDay: true,
        );

        expect(capturedStart!.hour, 0);
        expect(capturedStart!.minute, 0);
        expect(capturedStart!.second, 0);
        expect(capturedEnd!.hour, 0);
        expect(capturedEnd!.minute, 0);
        expect(capturedEnd!.second, 0);
      });

      test('throws ArgumentError when eventId is empty', () async {
        expect(
          () => DeviceCalendar.instance.updateEvent(
            eventId: '',
            title: 'New Title',
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when no fields provided', () async {
        expect(
          () => DeviceCalendar.instance.updateEvent(eventId: 'event-123'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when endDate is before startDate', () async {
        expect(
          () => DeviceCalendar.instance.updateEvent(
            eventId: 'event-123',
            startDate: DateTime(2024, 3, 20, 11, 0),
            endDate: DateTime(2024, 3, 20, 10, 0),
          ),
          throwsArgumentError,
        );
      });
    });

    group('deleteEvent', () {
      test('throws ArgumentError when instance ID is empty', () async {
        expect(
          () => DeviceCalendar.instance.deleteEvent(eventId: ''),
          throwsArgumentError,
        );
      });
    });

    group('showCreateEventModal', () {
      test('strips time components when isAllDay is true', () async {
        final start = DateTime(2024, 3, 15, 14, 30, 45);
        final end = DateTime(2024, 3, 16, 18, 15, 30);
        int? capturedStart;
        int? capturedEnd;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setShowCreateEventModalCallback(({
          title,
          startDate,
          endDate,
          description,
          location,
          isAllDay,
          recurrenceRule,
          availability,
        }) {
          capturedStart = startDate;
          capturedEnd = endDate;
          return Future.value();
        });
        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.showCreateEventModal(
          startDate: start,
          endDate: end,
          isAllDay: true,
        );

        expect(capturedStart, DateTime(2024, 3, 15).millisecondsSinceEpoch);
        expect(capturedEnd, DateTime(2024, 3, 16).millisecondsSinceEpoch);
      });

      test('throws ArgumentError when endDate before startDate', () async {
        final now = DateTime.now();
        expect(
          () => DeviceCalendar.instance.showCreateEventModal(
            startDate: now,
            endDate: now.subtract(Duration(hours: 1)),
          ),
          throwsArgumentError,
        );
      });

      test('converts PERMISSION_DENIED to DeviceCalendarException', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendar.instance.showCreateEventModal(),
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
