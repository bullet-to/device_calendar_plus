import 'dart:ui' show Color;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Arguments captured from the last [DeviceCalendarPlusPlatform.updateEvent]
/// call.
typedef UpdateEventCall = ({
  String eventId,
  int? timestamp,
  String? title,
  DateTime? startDate,
  DateTime? endDate,
  Patch<String>? description,
  Patch<String>? location,
  Patch<String>? url,
  bool? isAllDay,
  String? timeZone,
  String? availability,
  Patch<List<int>>? reminders,
});

/// Arguments captured from the last
/// [DeviceCalendarPlusPlatform.updateRecurring] call.
typedef UpdateRecurringCall = ({
  String eventId,
  int? timestamp,
  String span,
  String? title,
  DateTime? start,
  int? durationMinutes,
  Patch<String>? description,
  Patch<String>? location,
  Patch<String>? url,
  bool? isAllDay,
  String? timeZone,
  String? availability,
  Patch<String>? recurrenceRule,
});

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  String? _permissionStatusCode = "notDetermined";

  /// When set, the status [requestPermissions] returns (simulating the result
  /// of a prompt), distinct from the [hasPermissions] status.
  String? _postRequestStatusCode;

  /// How many times [requestPermissions] has been called.
  int requestPermissionsCallCount = 0;

  /// The `writeOnly` argument of the most recent requestPermissions call.
  bool? lastWriteOnly;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _event;
  PlatformException? _exceptionToThrow;

  /// The arguments of the most recent updateEvent / updateRecurring /
  /// updateCalendar / deleteEvent call.
  UpdateEventCall? lastUpdateEvent;
  UpdateRecurringCall? lastUpdateRecurring;

  /// The `reminders` (minutes) argument of the most recent createEvent call.
  /// Captured separately from [_createEventCallback] so existing callback
  /// callers keep their unchanged signature. Set to a sentinel before each
  /// captured call so "passed null" is distinguishable from "never called".
  Object? lastCreateEventReminders = 'unset';
  ({String calendarId, String? name, String? colorHex})? lastUpdateCalendar;
  ({String eventId, int? timestamp})? lastDeleteEvent;

  /// What updateRecurring returns (the affected scope's event ID).
  String updateRecurringResult = 'mock-event-id';

  // Callback to capture createEvent arguments
  Future<String> Function(
    String? calendarId,
    String title,
    DateTime startDate,
    DateTime endDate,
    bool isAllDay,
    String? description,
    String? location,
    String? url,
    String? timeZone,
    String availability,
    String? recurrenceRule,
  )? _createEventCallback;

  // Callback to capture deleteRecurring arguments
  Future<void> Function(
    String eventId,
    int? timestamp,
    String span,
  )? _deleteRecurringCallback;

  void setPermissionStatus(CalendarPermissionStatus status) {
    _permissionStatusCode = status.name;
  }

  /// Sets the status [requestPermissions] returns, as if a prompt resolved to
  /// it. Leave unset to have requestPermissions echo [setPermissionStatus].
  void setPostRequestStatus(CalendarPermissionStatus status) {
    _postRequestStatusCode = status.name;
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
      String? calendarId,
      String title,
      DateTime startDate,
      DateTime endDate,
      bool isAllDay,
      String? description,
      String? location,
      String? url,
      String? timeZone,
      String availability,
      String? recurrenceRule,
    ) callback,
  ) {
    _createEventCallback = callback;
  }

  void setDeleteRecurringCallback(
    Future<void> Function(
      String eventId,
      int? timestamp,
      String span,
    ) callback,
  ) {
    _deleteRecurringCallback = callback;
  }

  @override
  Future<String?> requestPermissions(bool writeOnly) async {
    lastWriteOnly = writeOnly;
    requestPermissionsCallCount++;
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    return _postRequestStatusCode ?? _permissionStatusCode;
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
    lastUpdateCalendar = (calendarId: calendarId, name: name, colorHex: colorHex);
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
  Future<void> showEventModal(String eventId, int? timestamp,
      {bool edit = false}) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
  }

  @override
  Future<String> createEvent(
    String? calendarId,
    String title,
    DateTime startDate,
    DateTime endDate,
    bool isAllDay,
    String? description,
    String? location,
    String? url,
    String? timeZone,
    String availability,
    String? recurrenceRule,
    List<int>? reminders,
  ) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    lastCreateEventReminders = reminders;
    if (_createEventCallback != null) {
      return _createEventCallback!(
        calendarId,
        title,
        startDate,
        endDate,
        isAllDay,
        description,
        location,
        url,
        timeZone,
        availability,
        recurrenceRule,
      );
    }
    return 'mock-event-id';
  }

  @override
  Future<void> deleteEvent(String eventId, {int? timestamp}) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    lastDeleteEvent = (eventId: eventId, timestamp: timestamp);
  }

  @override
  Future<void> updateEvent(
    String eventId, {
    int? timestamp,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
    bool? isAllDay,
    String? timeZone,
    String? availability,
    Patch<List<int>>? reminders,
  }) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    lastUpdateEvent = (
      eventId: eventId,
      timestamp: timestamp,
      title: title,
      startDate: startDate,
      endDate: endDate,
      description: description,
      location: location,
      url: url,
      isAllDay: isAllDay,
      timeZone: timeZone,
      availability: availability,
      reminders: reminders,
    );
  }

  @override
  Future<String> updateRecurring(
    String eventId,
    int? timestamp,
    String span, {
    String? title,
    DateTime? start,
    int? durationMinutes,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
    bool? isAllDay,
    String? timeZone,
    String? availability,
    Patch<String>? recurrenceRule,
  }) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    lastUpdateRecurring = (
      eventId: eventId,
      timestamp: timestamp,
      span: span,
      title: title,
      start: start,
      durationMinutes: durationMinutes,
      description: description,
      location: location,
      url: url,
      isAllDay: isAllDay,
      timeZone: timeZone,
      availability: availability,
      recurrenceRule: recurrenceRule,
    );
    return updateRecurringResult;
  }

  @override
  Future<void> deleteRecurring(
    String eventId,
    int? timestamp,
    String span,
  ) async {
    if (_exceptionToThrow != null) throw _exceptionToThrow!;
    if (_deleteRecurringCallback != null) {
      return _deleteRecurringCallback!(eventId, timestamp, span);
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
    // DeviceCalendar is a singleton, so reset the opt-in flag between tests.
    DeviceCalendar.instance.autoPermissions = null;
  });

  group('DeviceCalendar', () {
    group('requestPermissions', () {
      test('converts status code to CalendarPermissionStatus', () async {
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);
        final result = await DeviceCalendar.instance.requestPermissions();
        expect(result, CalendarPermissionStatus.granted);
      });

      test('defaults to requesting full access', () async {
        await DeviceCalendar.instance.requestPermissions();
        expect(mockPlatform.lastWriteOnly, isFalse);
      });

      test('forwards the requested access level to the platform', () async {
        await DeviceCalendar.instance.requestPermissions(
          level: CalendarAccessLevel.writeOnly,
        );
        expect(mockPlatform.lastWriteOnly, isTrue);
      });

      test('converts a granted write-only request to writeOnly', () async {
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.writeOnly);
        final result = await DeviceCalendar.instance.requestPermissions(
          level: CalendarAccessLevel.writeOnly,
        );
        expect(result, CalendarPermissionStatus.writeOnly);
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

    group('autoPermissions', () {
      Future<String> createAnEvent() => DeviceCalendar.instance.createEvent(
            calendarId: 'cal',
            title: 'Standup',
            startDate: DateTime(2026, 1, 1, 9),
            endDate: DateTime(2026, 1, 1, 10),
          );

      test('manual mode (null) never prompts, even when notDetermined',
          () async {
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        await DeviceCalendar.instance.listCalendars();
        expect(mockPlatform.requestPermissionsCallCount, 0);
      });

      test('full mode requests full access for a read op when notDetermined',
          () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        mockPlatform.setPostRequestStatus(CalendarPermissionStatus.granted);

        await DeviceCalendar.instance.listCalendars();

        expect(mockPlatform.requestPermissionsCallCount, 1);
        expect(mockPlatform.lastWriteOnly, isFalse);
      });

      test('asNeeded mode requests write-only for an add-only op', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        mockPlatform.setPostRequestStatus(CalendarPermissionStatus.writeOnly);

        await createAnEvent();

        expect(mockPlatform.lastWriteOnly, isTrue);
      });

      test('asNeeded mode requests full access for a read op', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        mockPlatform.setPostRequestStatus(CalendarPermissionStatus.granted);

        await DeviceCalendar.instance.listCalendars();

        expect(mockPlatform.lastWriteOnly, isFalse);
      });

      test('full mode requests full access even for an add-only op', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        mockPlatform.setPostRequestStatus(CalendarPermissionStatus.granted);

        await createAnEvent();

        expect(mockPlatform.lastWriteOnly, isFalse);
      });

      test('does not prompt when access is already granted', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);

        await DeviceCalendar.instance.listCalendars();

        expect(mockPlatform.requestPermissionsCallCount, 0);
      });

      test('a held write-only tier satisfies an add-only op without prompting',
          () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.writeOnly);

        await createAnEvent();

        expect(mockPlatform.requestPermissionsCallCount, 0);
      });

      test('does not auto-escalate a held write-only tier for a read op',
          () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.writeOnly);

        await expectLater(
          DeviceCalendar.instance.listCalendars(),
          throwsA(isA<DeviceCalendarException>().having(
            (e) => e.errorCode,
            'errorCode',
            DeviceCalendarError.permissionDenied,
          )),
        );
        expect(mockPlatform.requestPermissionsCallCount, 0);
      });

      test('a no-op update does not prompt (guard runs after the no-op return)',
          () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);

        // No changed fields: a valid no-op that must not trigger a prompt.
        await DeviceCalendar.instance.updateEvent(eventId: 'evt');

        expect(mockPlatform.requestPermissionsCallCount, 0);
      });

      test('throws permissionDenied when access is denied', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.denied);

        await expectLater(
          DeviceCalendar.instance.listCalendars(),
          throwsA(isA<DeviceCalendarException>().having(
            (e) => e.errorCode,
            'errorCode',
            DeviceCalendarError.permissionDenied,
          )),
        );
      });

      test('throws permissionDenied when the prompt is declined', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        mockPlatform.setPostRequestStatus(CalendarPermissionStatus.denied);

        await expectLater(
          DeviceCalendar.instance.listCalendars(),
          throwsA(isA<DeviceCalendarException>().having(
            (e) => e.errorCode,
            'errorCode',
            DeviceCalendarError.permissionDenied,
          )),
        );
      });

      test('asNeeded does not prompt when already fully granted', () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);

        await DeviceCalendar.instance.listCalendars();

        expect(mockPlatform.requestPermissionsCallCount, 0);
      });

      test('prompts at most once per tier per run, even after a soft-deny',
          () async {
        DeviceCalendar.instance.autoPermissions = AutoPermissionMode.full;
        // notDetermined = Android "can ask again"; the request itself is declined.
        mockPlatform.setPermissionStatus(CalendarPermissionStatus.notDetermined);
        mockPlatform.setPostRequestStatus(CalendarPermissionStatus.denied);

        await expectLater(
          DeviceCalendar.instance.listCalendars(),
          throwsA(isA<DeviceCalendarException>()),
        );
        await expectLater(
          DeviceCalendar.instance.listCalendars(),
          throwsA(isA<DeviceCalendarException>()),
        );

        // Only the first call prompted; the second failed fast without re-asking.
        expect(mockPlatform.requestPermissionsCallCount, 1);
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
          url,
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
          url,
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

      test('throws ArgumentError when calendar ID is whitespace', () async {
        expect(
          () => DeviceCalendar.instance.createEvent(
            calendarId: '   ',
            title: 'Meeting',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(Duration(hours: 1)),
          ),
          throwsArgumentError,
        );
      });

      test('forwards null calendarId to the platform when omitted', () async {
        const sentinel = 'unset';
        Object? capturedCalendarId = sentinel;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setCreateEventCallback((
          calendarId,
          title,
          startDate,
          endDate,
          isAllDay,
          description,
          location,
          url,
          timeZone,
          availability,
          recurrenceRule,
        ) {
          capturedCalendarId = calendarId;
          return Future.value('event-id');
        });

        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.createEvent(
          title: 'Default Calendar Event',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(hours: 1)),
        );

        expect(capturedCalendarId, isNull);
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

      test('forwards reminders to the platform as whole minutes', () async {
        await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'Meeting',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(hours: 1)),
          reminders: [
            Duration(minutes: 15),
            Duration(hours: 1),
            Duration(seconds: 90),
          ],
        );

        expect(mockPlatform.lastCreateEventReminders, [15, 60, 2]);
      });

      test('forwards null reminders when omitted', () async {
        await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'Meeting',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(hours: 1)),
        );

        expect(mockPlatform.lastCreateEventReminders, isNull);
      });

      test('allows a zero-duration reminder (at start)', () async {
        await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'Meeting',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(hours: 1)),
          reminders: [Duration.zero],
        );

        expect(mockPlatform.lastCreateEventReminders, [0]);
      });

      test('de-duplicates reminders that round to the same minute', () async {
        await DeviceCalendar.instance.createEvent(
          calendarId: 'cal-123',
          title: 'Meeting',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(hours: 1)),
          reminders: [Duration(minutes: 15), Duration(seconds: 900)],
        );

        expect(mockPlatform.lastCreateEventReminders, [15]);
      });

      test('throws ArgumentError on a negative reminder', () async {
        expect(
          () => DeviceCalendar.instance.createEvent(
            calendarId: 'cal-123',
            title: 'Meeting',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(Duration(hours: 1)),
            reminders: [Duration(minutes: -5)],
          ),
          throwsArgumentError,
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
      test('is a no-op when no parameters provided', () async {
        await DeviceCalendar.instance.updateCalendar('calendar-123');
        // Nothing to change -> short-circuits before any platform write.
        expect(mockPlatform.lastUpdateCalendar, isNull);
      });

      test('throws ArgumentError when name is empty', () async {
        expect(
          () =>
              DeviceCalendar.instance.updateCalendar('calendar-123', name: ''),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when calendarId is empty', () async {
        expect(
          () => DeviceCalendar.instance.updateCalendar('   ', name: 'x'),
          throwsArgumentError,
        );
      });
    });

    group('updateEvent', () {
      test('normalizes dates when isAllDay is true', () async {
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123',
          startDate: DateTime(2024, 3, 15, 14, 30, 45),
          endDate: DateTime(2024, 3, 16, 18, 15, 30),
          isAllDay: true,
        );

        final call = mockPlatform.lastUpdateEvent!;
        expect(call.startDate, DateTime(2024, 3, 15));
        expect(call.endDate, DateTime(2024, 3, 16));
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

      test('is a no-op when no fields provided', () async {
        await DeviceCalendar.instance.updateEvent(eventId: 'event-123');
        // Short-circuits before any platform write.
        expect(mockPlatform.lastUpdateEvent, isNull);
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

      test('passes a reminders Patch.set through as minutes', () async {
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123',
          reminders: Patch.set([Duration(minutes: 30), Duration(seconds: 90)]),
        );

        final reminders = mockPlatform.lastUpdateEvent?.reminders;
        expect(reminders, isA<PatchSet<List<int>>>());
        expect((reminders as PatchSet<List<int>>).value, [30, 2]);
      });

      test('passes a reminders Patch.clear through unchanged', () async {
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123',
          reminders: const Patch.clear(),
        );

        expect(
          mockPlatform.lastUpdateEvent?.reminders,
          isA<PatchClear<List<int>>>(),
        );
      });

      test('reminders alone is enough to not be a no-op', () async {
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123',
          reminders: const Patch.clear(),
        );
        expect(mockPlatform.lastUpdateEvent, isNotNull);
      });

      test('throws ArgumentError on a negative reminder in Patch.set', () async {
        expect(
          () => DeviceCalendar.instance.updateEvent(
            eventId: 'event-123',
            reminders: Patch.set([Duration(minutes: -5)]),
          ),
          throwsArgumentError,
        );
      });
    });

    group('updateRecurring', () {
      test('throws ArgumentError when instanceId is empty', () {
        expect(
          () => DeviceCalendar.instance.updateRecurring(
            '',
            EventSpan.allEvents,
            title: 'New Title',
          ),
          throwsArgumentError,
        );
      });

      test('is a no-op returning the targeted event id when no fields provided',
          () async {
        final result = await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
        );
        // Returns the scope the caller named, and skips the platform write.
        expect(result, 'event-123');
        expect(mockPlatform.lastUpdateRecurring, isNull);
      });

      test('throws ArgumentError when thisAndFollowing given a bare event ID',
          () {
        expect(
          () => DeviceCalendar.instance.updateRecurring(
            'event-123',
            EventSpan.thisAndFollowing,
            title: 'New Title',
          ),
          throwsArgumentError,
        );
      });

      test('accepts start on an all-day event (only the date is used)',
          () async {
        // start carries a time, but all-day events have no time-of-day; the
        // platform layer uses only the date. No contradiction to reject.
        final result = await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          isAllDay: true,
          start: DateTime(2024, 3, 19, 10, 0),
        );
        expect(result, 'mock-event-id');
        expect(mockPlatform.lastUpdateRecurring?.start, DateTime(2024, 3, 19, 10, 0));
      });

      test('throws ArgumentError when isAllDay is true with sub-day duration',
          () {
        expect(
          () => DeviceCalendar.instance.updateRecurring(
            'event-123',
            EventSpan.allEvents,
            isAllDay: true,
            duration: const Duration(hours: 2),
          ),
          throwsArgumentError,
        );
      });

      test('allows isAllDay with whole-day duration', () async {
        final result = await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          isAllDay: true,
          duration: const Duration(days: 3),
        );
        expect(result, 'mock-event-id');
      });

      test(
          'throws ArgumentError when isAllDay duration is a whole day plus '
          'a sub-minute remainder', () {
        expect(
          () => DeviceCalendar.instance.updateRecurring(
            'event-123',
            EventSpan.allEvents,
            isAllDay: true,
            duration: const Duration(days: 1, seconds: 30),
          ),
          throwsArgumentError,
        );
      });

      test('accepts a zero duration (instantaneous event)', () async {
        // Zero-duration events are supported (createEvent allows
        // endDate == startDate; listEvents returns them, #416), so updating a
        // series to one must not be rejected. Negative durations still throw.
        final result = await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          duration: Duration.zero,
        );
        expect(result, 'mock-event-id');
        expect(mockPlatform.lastUpdateRecurring?.durationMinutes, 0);
      });

      test('throws ArgumentError when duration is negative', () {
        expect(
          () => DeviceCalendar.instance.updateRecurring(
            'event-123',
            EventSpan.allEvents,
            duration: const Duration(minutes: -30),
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when duration is not whole minutes', () {
        expect(
          () => DeviceCalendar.instance.updateRecurring(
            'event-123',
            EventSpan.allEvents,
            duration: const Duration(minutes: 90, seconds: 30),
          ),
          throwsArgumentError,
        );
      });

      test('allEvents accepts a bare event ID (no occurrence timestamp)',
          () async {
        final result = await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          title: 'New Title',
        );
        expect(result, 'mock-event-id');
      });

      test('passes start to the platform', () async {
        await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          start: DateTime(2024, 3, 18, 15, 30),
        );

        expect(
          mockPlatform.lastUpdateRecurring?.start,
          DateTime(2024, 3, 18, 15, 30),
        );
      });

      test('passes duration as minutes to the platform', () async {
        await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          duration: const Duration(hours: 1, minutes: 30),
        );

        expect(mockPlatform.lastUpdateRecurring?.durationMinutes, 90);
      });

      test('passes the span name and parsed instance ID to the platform',
          () async {
        mockPlatform.updateRecurringResult = 'new-series-id';

        final result = await DeviceCalendar.instance.updateRecurring(
          'event-123@1700000000000',
          EventSpan.thisAndFollowing,
          title: 'New Title',
        );

        final call = mockPlatform.lastUpdateRecurring!;
        expect(call.eventId, 'event-123');
        expect(call.timestamp, 1700000000000);
        expect(call.span, 'thisAndFollowing');
        expect(result, 'new-series-id');
      });

      test('converts a RecurrenceRule patch to an RRULE string', () async {
        await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          recurrenceRule: Patch.set(const DailyRecurrence(end: CountEnd(5))),
        );

        final rule = mockPlatform.lastUpdateRecurring?.recurrenceRule;
        expect(rule, isA<PatchSet<String>>());
        expect((rule as PatchSet<String>).value, 'FREQ=DAILY;COUNT=5');
      });

      test('passes a cleared recurrence rule through as Patch.clear', () async {
        await DeviceCalendar.instance.updateRecurring(
          'event-123',
          EventSpan.allEvents,
          recurrenceRule: const Patch.clear(),
        );

        expect(
          mockPlatform.lastUpdateRecurring?.recurrenceRule,
          isA<PatchClear<String>>(),
        );
      });
    });

    group('updateEvent with instance ID', () {
      test('passes the parsed event ID and occurrence timestamp through',
          () async {
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123@1700000000000',
          title: 'Moved this week',
        );

        final call = mockPlatform.lastUpdateEvent!;
        expect(call.eventId, 'event-123');
        expect(call.timestamp, 1700000000000);
        expect(call.title, 'Moved this week');
      });

      test('passes full start and end dates, so the occurrence can move days',
          () async {
        // Occurrence on 2023-11-14 (1700000000000ms); the edit moves it to a
        // different day entirely. The dates must arrive intact — not reduced
        // to a time-of-day.
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123@1700000000000',
          startDate: DateTime(2024, 3, 20, 14, 0),
          endDate: DateTime(2024, 3, 20, 14, 30),
        );

        final call = mockPlatform.lastUpdateEvent!;
        expect(call.timestamp, 1700000000000);
        expect(call.startDate, DateTime(2024, 3, 20, 14, 0));
        expect(call.endDate, DateTime(2024, 3, 20, 14, 30));
      });

      test('bare event ID passes a null timestamp', () async {
        await DeviceCalendar.instance.updateEvent(
          eventId: 'event-123',
          title: 'New Title',
        );

        final call = mockPlatform.lastUpdateEvent!;
        expect(call.eventId, 'event-123');
        expect(call.timestamp, isNull);
      });
    });

    group('deleteRecurring', () {
      test('throws ArgumentError when instanceId is empty', () {
        expect(
          () => DeviceCalendar.instance.deleteRecurring(
            '',
            EventSpan.allEvents,
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError when thisAndFollowing given a bare event ID',
          () {
        expect(
          () => DeviceCalendar.instance.deleteRecurring(
            'event-123',
            EventSpan.thisAndFollowing,
          ),
          throwsArgumentError,
        );
      });

      test('allEvents passes a bare event ID through with null timestamp',
          () async {
        String? capturedEventId;
        int? capturedTimestamp;
        String? capturedSpan;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setDeleteRecurringCallback((eventId, timestamp, span) {
          capturedEventId = eventId;
          capturedTimestamp = timestamp;
          capturedSpan = span;
          return Future.value();
        });
        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.deleteRecurring(
          'event-123',
          EventSpan.allEvents,
        );

        expect(capturedEventId, 'event-123');
        expect(capturedTimestamp, isNull);
        expect(capturedSpan, 'allEvents');
      });

      test('passes the span name and parsed instance ID to the platform',
          () async {
        String? capturedEventId;
        int? capturedTimestamp;
        String? capturedSpan;

        final mock = MockDeviceCalendarPlusPlatform();
        mock.setDeleteRecurringCallback((eventId, timestamp, span) {
          capturedEventId = eventId;
          capturedTimestamp = timestamp;
          capturedSpan = span;
          return Future.value();
        });
        DeviceCalendarPlusPlatform.instance = mock;

        await DeviceCalendar.instance.deleteRecurring(
          'event-123@1700000000000',
          EventSpan.thisAndFollowing,
        );

        expect(capturedEventId, 'event-123');
        expect(capturedTimestamp, 1700000000000);
        expect(capturedSpan, 'thisAndFollowing');
      });
    });

    group('deleteEvent', () {
      test('throws ArgumentError when instance ID is empty', () async {
        expect(
          () => DeviceCalendar.instance.deleteEvent(eventId: ''),
          throwsArgumentError,
        );
      });

      test('bare event ID passes a null timestamp', () async {
        await DeviceCalendar.instance.deleteEvent(eventId: 'event-123');

        final call = mockPlatform.lastDeleteEvent!;
        expect(call.eventId, 'event-123');
        expect(call.timestamp, isNull);
      });

      test('passes the parsed event ID and occurrence timestamp through',
          () async {
        await DeviceCalendar.instance.deleteEvent(
          eventId: 'event-123@1700000000000',
        );

        final call = mockPlatform.lastDeleteEvent!;
        expect(call.eventId, 'event-123');
        expect(call.timestamp, 1700000000000);
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

  group('Calendar.color', () {
    Calendar cal({String? colorHex}) => Calendar(
          id: '1',
          name: 'Test',
          colorHex: colorHex,
          readOnly: false,
        );

    test('parses 6-digit hex with # prefix', () {
      expect(cal(colorHex: '#FF0000').color, const Color(0xFFFF0000));
    });

    test('parses 8-digit hex with alpha', () {
      expect(cal(colorHex: '#80FF0000').color, const Color(0x80FF0000));
    });

    test('parses without # prefix', () {
      expect(cal(colorHex: '00FF00').color, const Color(0xFF00FF00));
    });

    test('returns null when colorHex is null', () {
      expect(cal().color, isNull);
    });

    test('returns null for unparseable string', () {
      expect(cal(colorHex: 'notacolor').color, isNull);
    });
  });

  group('Event', () {
    Map<String, dynamic> baseMap({List<int>? reminders}) => {
          'eventId': 'e1',
          'instanceId': 'e1',
          'calendarId': 'c1',
          'title': 'Standup',
          'startDate': DateTime(2024, 1, 1, 9).millisecondsSinceEpoch,
          'endDate': DateTime(2024, 1, 1, 10).millisecondsSinceEpoch,
          'isAllDay': false,
          'availability': 'busy',
          'status': 'confirmed',
          'isRecurring': false,
          if (reminders != null) 'reminders': reminders,
        };

    group('fromMap', () {
      test('parses reminders minutes into a List<Duration>', () {
        final event = Event.fromMap(baseMap(reminders: [15, 60, 0]));
        expect(event.reminders, [
          const Duration(minutes: 15),
          const Duration(hours: 1),
          Duration.zero,
        ]);
      });

      test('leaves reminders null when the platform reports none', () {
        final event = Event.fromMap(baseMap());
        expect(event.reminders, isNull);
      });
    });

    group('toMap', () {
      test('serializes reminders back to minutes', () {
        final event = Event.fromMap(baseMap(reminders: [15, 60]));
        expect(event.toMap()['reminders'], [15, 60]);
      });

      test('round-trips reminders through fromMap -> toMap -> fromMap', () {
        final original = Event.fromMap(baseMap(reminders: [5, 30, 1440]));
        final roundTripped = Event.fromMap(
          Map<String, dynamic>.from(original.toMap()),
        );
        expect(roundTripped.reminders, original.reminders);
      });

      test('omits reminders when null', () {
        final event = Event.fromMap(baseMap());
        expect(event.toMap().containsKey('reminders'), isFalse);
      });
    });
  });
}
