import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';

import 'src/calendar.dart';
import 'src/calendar_permission_status.dart';
import 'src/event.dart';
import 'src/event_availability.dart';
import 'src/platform_exception_converter.dart';

export 'src/calendar.dart';
export 'src/calendar_permission_status.dart';
export 'src/device_calendar_error.dart';
export 'src/event.dart';
export 'src/event_availability.dart';
export 'src/event_status.dart';
export 'src/platform_exception_codes.dart';

/// Main API for accessing device calendar functionality.
class DeviceCalendar {
  DeviceCalendar._internal();

  static final DeviceCalendar instance = DeviceCalendar._internal();

  factory DeviceCalendar() => instance;

  /// Returns the platform version (e.g., "Android 13", "iOS 17.0").
  Future<String?> getPlatformVersion() {
    return DeviceCalendarPlusPlatform.instance.getPlatformVersion();
  }

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// Returns a [CalendarPermissionStatus] indicating the result
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// final status = await plugin.requestPermissions();
  /// if (status == CalendarPermissionStatus.granted) {
  ///   // Access calendars
  /// } else if (status == CalendarPermissionStatus.denied) {
  ///   // Show "Enable in Settings" message
  /// } else if (status == CalendarPermissionStatus.restricted) {
  ///   // Show "Contact administrator" message
  /// }
  /// ```
  Future<CalendarPermissionStatus> requestPermissions() async {
    return _handlePermissionRequest(
      () => DeviceCalendarPlusPlatform.instance.requestPermissions(),
    );
  }

  /// Checks the current calendar permission status WITHOUT requesting permissions.
  ///
  /// Unlike [requestPermissions], this method will NOT prompt the user for
  /// permissions if they haven't been granted yet. It only checks the current status.
  ///
  /// Use this method if you want to check permissions before deciding whether
  /// to call [requestPermissions], or when you want to verify permissions without
  /// triggering the system permission dialog.
  ///
  /// Returns the current [CalendarPermissionStatus].
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// final status = await plugin.hasPermissions();
  /// if (status == CalendarPermissionStatus.granted) {
  ///   // Permissions already granted
  ///   final calendars = await plugin.listCalendars();
  /// } else if (status == CalendarPermissionStatus.notDetermined) {
  ///   // User hasn't been asked yet
  ///   final newStatus = await plugin.requestPermissions();
  /// }
  /// ```
  Future<CalendarPermissionStatus> hasPermissions() async {
    return _handlePermissionRequest(
      () => DeviceCalendarPlusPlatform.instance.hasPermissions(),
    );
  }

  /// Helper method to handle permission requests and convert status values
  Future<CalendarPermissionStatus> _handlePermissionRequest(
    Future<String?> Function() permissionCall,
  ) async {
    try {
      final String? statusValue = await permissionCall();
      return _convertStatusValue(statusValue);
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Converts a status value string to CalendarPermissionStatus
  CalendarPermissionStatus _convertStatusValue(String? statusValue) {
    // Default to denied if status is null or unrecognized
    if (statusValue == null) {
      return CalendarPermissionStatus.denied;
    }

    // Parse the enum value by name
    try {
      return CalendarPermissionStatus.values.firstWhere(
        (e) => e.name == statusValue,
        orElse: () => CalendarPermissionStatus.denied,
      );
    } catch (_) {
      return CalendarPermissionStatus.denied;
    }
  }

  /// Lists all calendars available on the device.
  ///
  /// Returns a list of [Calendar] objects representing each calendar.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// final calendars = await plugin.listCalendars();
  /// for (final calendar in calendars) {
  ///   print('${calendar.name} (${calendar.id})');
  ///   print('  Read-only: ${calendar.readOnly}');
  ///   print('  Primary: ${calendar.isPrimary}');
  ///   print('  Color: ${calendar.colorHex}');
  /// }
  /// ```
  Future<List<Calendar>> listCalendars() async {
    try {
      final List<Map<String, dynamic>> rawCalendars =
          await DeviceCalendarPlusPlatform.instance.listCalendars();
      return rawCalendars.map((map) => Calendar.fromMap(map)).toList();
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Creates a new calendar on the device.
  ///
  /// [name] is the display name for the calendar (required).
  /// [colorHex] is an optional color in #RRGGBB format (e.g., "#FF5733").
  ///
  /// Returns the ID of the newly created calendar.
  ///
  /// The calendar is created in the device's local storage.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Create a calendar with just a name
  /// final calendarId = await plugin.createCalendar(name: 'My Calendar');
  ///
  /// // Create a calendar with a name and color
  /// final coloredCalendarId = await plugin.createCalendar(
  ///   name: 'Work Calendar',
  ///   colorHex: '#FF5733',
  /// );
  /// ```
  Future<String> createCalendar({
    required String name,
    String? colorHex,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Calendar name cannot be empty',
      );
    }

    try {
      final String calendarId = await DeviceCalendarPlusPlatform.instance
          .createCalendar(name, colorHex);
      return calendarId;
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Updates an existing calendar on the device.
  ///
  /// [calendarId] is the ID of the calendar to update.
  /// [name] is the new display name for the calendar (optional).
  /// [colorHex] is the new color in #RRGGBB format (optional, e.g., "#FF5733").
  ///
  /// At least one of [name] or [colorHex] must be provided.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Update just the name
  /// await plugin.updateCalendar(calendarId, name: 'New Name');
  ///
  /// // Update just the color
  /// await plugin.updateCalendar(calendarId, colorHex: '#FF5733');
  ///
  /// // Update both name and color
  /// await plugin.updateCalendar(
  ///   calendarId,
  ///   name: 'New Name',
  ///   colorHex: '#FF5733',
  /// );
  /// ```
  Future<void> updateCalendar(
    String calendarId, {
    String? name,
    String? colorHex,
  }) async {
    // Validate that at least one parameter is provided
    if (name == null && colorHex == null) {
      throw ArgumentError(
        'At least one of name or colorHex must be provided',
      );
    }

    // Validate name if provided
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Calendar name cannot be empty',
      );
    }

    try {
      await DeviceCalendarPlusPlatform.instance
          .updateCalendar(calendarId, name, colorHex);
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Deletes a calendar from the device.
  ///
  /// [calendarId] is the ID of the calendar to delete.
  ///
  /// This will also delete all events within the calendar.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Delete a calendar by ID
  /// await plugin.deleteCalendar(calendarId);
  /// ```
  Future<void> deleteCalendar(String calendarId) async {
    try {
      await DeviceCalendarPlusPlatform.instance.deleteCalendar(calendarId);
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Lists events within the specified date range.
  ///
  /// [startDate] and [endDate] are required parameters that define the time
  /// window for fetching events.
  ///
  /// **Important iOS Limitation**: iOS automatically limits event queries to a
  /// maximum span of 4 years. If you specify a range exceeding 4 years, iOS
  /// will truncate it to the first 4 years automatically.
  ///
  /// [calendarIds] is an optional parameter to filter events to specific
  /// calendars. If null or empty, events from all calendars are returned.
  ///
  /// Recurring events are automatically expanded into individual instances
  /// within the date range. Each instance has:
  /// - The same [Event.eventId]
  /// - Different [Event.startDate] and [Event.endDate]
  ///
  /// This combination uniquely identifies each occurrence of a recurring event.
  ///
  /// Returns a list of [Event] objects sorted by start date.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// final now = DateTime.now();
  /// final nextMonth = now.add(Duration(days: 30));
  ///
  /// // Get all events in the next month
  /// final events = await plugin.listEvents(
  ///   now,
  ///   nextMonth,
  /// );
  ///
  /// // Get events from specific calendars only
  /// final workEvents = await plugin.listEvents(
  ///   now,
  ///   nextMonth,
  ///   calendarIds: ['work-calendar-id', 'project-calendar-id'],
  /// );
  ///
  /// for (final event in events) {
  ///   print('${event.title} at ${event.startDate}');
  /// }
  /// ```
  Future<List<Event>> listEvents(
    DateTime startDate,
    DateTime endDate, {
    List<String>? calendarIds,
  }) async {
    try {
      final List<Map<String, dynamic>> rawEvents =
          await DeviceCalendarPlusPlatform.instance.listEvents(
        startDate,
        endDate,
        calendarIds,
      );
      return rawEvents.map((map) => Event.fromMap(map)).toList();
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Retrieves a single event by instance ID.
  ///
  /// The [instanceId] uniquely identifies the event instance. You should obtain
  /// this from an Event object via `event.instanceId`, not construct it manually.
  ///
  /// **For recurring events:**
  /// - Use the `instanceId` to get a specific occurrence
  /// - Use the `eventId` to get the master event definition
  ///
  /// Returns null if no matching event is found.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// // Get specific instance of a recurring event
  /// final instance = await plugin.getEvent(event.instanceId);
  ///
  /// // Get master event definition for a recurring event
  /// final masterEvent = await plugin.getEvent(event.eventId);
  /// ```
  Future<Event?> getEvent(String instanceId) async {
    try {
      final Map<String, dynamic>? rawEvent =
          await DeviceCalendarPlusPlatform.instance.getEvent(instanceId);

      if (rawEvent == null) {
        return null;
      }

      return Event.fromMap(rawEvent);
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Shows a calendar event in a modal dialog.
  ///
  /// The [instanceId] uniquely identifies the event instance. You should obtain
  /// this from an Event object via `event.instanceId`, not construct it manually.
  ///
  /// **For recurring events:**
  /// - Use the `instanceId` to show a specific occurrence
  /// - Use the `eventId` to show the master event definition
  ///
  /// **Platform Differences:**
  /// - **iOS**: Presents the event in a native modal using EventKit's
  ///   `EKEventViewController`. The user can view and edit the event without
  ///   leaving your app. Requires your app to be in the foreground.
  /// - **Android**: Opens the event using an Intent with `ACTION_VIEW`.
  ///   The system handles the presentation based on device and app configuration.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// // Show specific instance of a recurring event
  /// await plugin.showEventModal(event.instanceId);
  ///
  /// // Show master event definition
  /// await plugin.showEventModal(event.eventId);
  /// ```
  Future<void> showEventModal(String instanceId) async {
    try {
      await DeviceCalendarPlusPlatform.instance.showEventModal(instanceId);
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Creates a new event in the specified calendar.
  ///
  /// [calendarId] is the ID of the calendar to create the event in (required).
  /// [title] is the event title (required).
  /// [startDate] is the start date/time (required).
  /// [endDate] is the end date/time (required).
  /// [isAllDay] indicates if this is an all-day event (default: false).
  /// [description] is optional event notes/description.
  /// [location] is optional event location.
  /// [timeZone] is optional timezone identifier (null for all-day events).
  ///   The platform will validate the timezone string.
  /// [url] is optional event URL (supported on both platforms).
  /// [availability] is the availability status (default: EventAvailability.busy).
  ///
  /// Returns the system-generated event ID.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Create a basic event
  /// final eventId = await plugin.createEvent(
  ///   calendarId: 'cal-123',
  ///   title: 'Team Meeting',
  ///   startDate: DateTime.now(),
  ///   endDate: DateTime.now().add(Duration(hours: 1)),
  /// );
  ///
  /// // Create an event with all options
  /// final detailedEventId = await plugin.createEvent(
  ///   calendarId: 'cal-123',
  ///   title: 'Project Review',
  ///   startDate: DateTime(2024, 3, 15, 14, 0),
  ///   endDate: DateTime(2024, 3, 15, 15, 0),
  ///   description: 'Q1 project review meeting',
  ///   location: 'Conference Room A',
  ///   timeZone: 'America/New_York',
  ///   availability: EventAvailability.busy,
  /// );
  /// ```
  Future<String> createEvent({
    required String calendarId,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    bool isAllDay = false,
    String? description,
    String? location,
    String? timeZone,
    EventAvailability availability = EventAvailability.busy,
  }) async {
    // Validate required fields
    if (calendarId.trim().isEmpty) {
      throw ArgumentError.value(
        calendarId,
        'calendarId',
        'Calendar ID cannot be empty',
      );
    }

    if (title.trim().isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Event title cannot be empty',
      );
    }

    if (endDate.isBefore(startDate)) {
      throw ArgumentError(
        'End date must be after start date',
      );
    }

    // Normalize dates for all-day events
    // All-day events should use midnight (00:00:00) and ignore time components
    DateTime normalizedStartDate = startDate;
    DateTime normalizedEndDate = endDate;

    if (isAllDay) {
      normalizedStartDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      normalizedEndDate = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
      );
    }

    try {
      final String eventId =
          await DeviceCalendarPlusPlatform.instance.createEvent(
        calendarId,
        title,
        normalizedStartDate,
        normalizedEndDate,
        isAllDay,
        description,
        location,
        timeZone,
        availability.name,
      );
      return eventId;
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Deletes an event from the device.
  ///
  /// [instanceId] uniquely identifies the event instance to delete.
  /// You should obtain this from an Event object via `event.instanceId`.
  ///
  /// [deleteAllInstances] determines deletion behavior for recurring events:
  /// - false (default): Deletes only this specific instance
  /// - true: Deletes all instances of the recurring event
  ///
  /// For non-recurring events, [deleteAllInstances] has no effect.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// **Note**: Deleting single instances of recurring events may not be fully
  /// supported on all platforms. If unsupported, an error will be thrown.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Delete a single event
  /// await plugin.deleteEvent(event.instanceId);
  ///
  /// // Delete all instances of a recurring event
  /// await plugin.deleteEvent(
  ///   event.instanceId,
  ///   deleteAllInstances: true,
  /// );
  /// ```
  Future<void> deleteEvent(
    String instanceId, {
    bool deleteAllInstances = false,
  }) async {
    if (instanceId.trim().isEmpty) {
      throw ArgumentError.value(
        instanceId,
        'instanceId',
        'Instance ID cannot be empty',
      );
    }

    try {
      await DeviceCalendarPlusPlatform.instance
          .deleteEvent(instanceId, deleteAllInstances);
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }

  /// Updates an existing event on the device.
  ///
  /// [instanceId] uniquely identifies the event instance to update (required).
  /// You should obtain this from an Event object via `event.instanceId`.
  ///
  /// [updateAllInstances] determines update behavior for recurring events:
  /// - false (default): Updates only this specific instance
  /// - true: Updates all instances of the recurring event
  ///
  /// All field parameters are optional - only provided fields will be updated:
  /// - [title] - new event title
  /// - [startDate] - new start date/time
  /// - [endDate] - new end date/time
  /// - [description] - new event description
  /// - [location] - new event location
  /// - [isAllDay] - change between all-day and timed event
  ///   - Changing timed → all-day: Time components are stripped to midnight
  ///   - Changing all-day → timed: Midnight time is used
  /// - [timeZone] - new timezone identifier
  ///   - Note: This reinterprets the local time, not preserving the instant
  ///   - Example: "3:00 PM EST" → "3:00 PM PST" (different instant in time)
  ///
  /// At least one field must be provided.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// **Note**: Updating single instances of recurring events may not be fully
  /// supported on all platforms. If unsupported, an error will be thrown.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Update event title
  /// await plugin.updateEvent(
  ///   instanceId: event.instanceId,
  ///   title: 'Updated Meeting Title',
  /// );
  ///
  /// // Change timed event to all-day
  /// await plugin.updateEvent(
  ///   instanceId: event.instanceId,
  ///   isAllDay: true,
  /// );
  ///
  /// // Update multiple fields
  /// await plugin.updateEvent(
  ///   instanceId: event.instanceId,
  ///   title: 'Team Sync',
  ///   startDate: DateTime(2024, 3, 20, 10, 0),
  ///   endDate: DateTime(2024, 3, 20, 11, 0),
  ///   location: 'Conference Room B',
  /// );
  ///
  /// // Update all instances of recurring event
  /// await plugin.updateEvent(
  ///   instanceId: event.instanceId,
  ///   updateAllInstances: true,
  ///   title: 'Updated Recurring Event',
  /// );
  /// ```
  Future<void> updateEvent({
    required String instanceId,
    bool updateAllInstances = false,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
  }) async {
    // Validate instanceId
    if (instanceId.trim().isEmpty) {
      throw ArgumentError.value(
        instanceId,
        'instanceId',
        'Instance ID cannot be empty',
      );
    }

    // Validate at least one field is provided
    if (title == null &&
        startDate == null &&
        endDate == null &&
        description == null &&
        location == null &&
        isAllDay == null &&
        timeZone == null) {
      throw ArgumentError(
        'At least one field must be provided to update',
      );
    }

    // Validate dates if both are provided
    if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
      throw ArgumentError(
        'End date must be after start date',
      );
    }

    // Normalize dates for all-day events
    // We need to check if the event is becoming all-day or if we're updating dates on an existing all-day event
    // Since we don't have access to the existing event here, we'll let the platform handle it
    // But if isAllDay is being set to true, we should normalize the dates
    DateTime? normalizedStartDate = startDate;
    DateTime? normalizedEndDate = endDate;

    if (isAllDay == true) {
      // Event is becoming all-day, normalize dates to midnight
      if (startDate != null) {
        normalizedStartDate = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        );
      }
      if (endDate != null) {
        normalizedEndDate = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
        );
      }
    }

    try {
      await DeviceCalendarPlusPlatform.instance.updateEvent(
        instanceId,
        updateAllInstances,
        title: title,
        startDate: normalizedStartDate,
        endDate: normalizedEndDate,
        description: description,
        location: location,
        isAllDay: isAllDay,
        timeZone: timeZone,
      );
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
  }
}
