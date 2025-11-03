import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';

import 'src/calendar.dart';
import 'src/calendar_permission_status.dart';
import 'src/event.dart';
import 'src/platform_exception_converter.dart';

export 'src/calendar.dart';
export 'src/calendar_permission_status.dart';
export 'src/device_calendar_error.dart';
export 'src/event.dart';
export 'src/event_availability.dart';
export 'src/event_status.dart';

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
    try {
      final int? statusCode =
          await DeviceCalendarPlusPlatform.instance.requestPermissions();
      // Default to denied if status is null or out of range
      if (statusCode == null ||
          statusCode < 0 ||
          statusCode >= CalendarPermissionStatus.values.length) {
        return CalendarPermissionStatus.denied;
      }
      return CalendarPermissionStatus.values[statusCode];
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
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

  /// Retrieves events within the specified date range.
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
  /// final events = await plugin.retrieveEvents(
  ///   now,
  ///   nextMonth,
  /// );
  ///
  /// // Get events from specific calendars only
  /// final workEvents = await plugin.retrieveEvents(
  ///   now,
  ///   nextMonth,
  ///   calendarIds: ['work-calendar-id', 'project-calendar-id'],
  /// );
  ///
  /// for (final event in events) {
  ///   print('${event.title} at ${event.startDate}');
  /// }
  /// ```
  Future<List<Event>> retrieveEvents(
    DateTime startDate,
    DateTime endDate, {
    List<String>? calendarIds,
  }) async {
    try {
      final List<Map<String, dynamic>> rawEvents =
          await DeviceCalendarPlusPlatform.instance.retrieveEvents(
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
  /// await plugin.showEvent(event.instanceId);
  ///
  /// // Show master event definition
  /// await plugin.showEvent(event.eventId);
  /// ```
  Future<void> showEvent(String instanceId) async {
    try {
      await DeviceCalendarPlusPlatform.instance.showEvent(instanceId);
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
