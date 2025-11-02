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
class DeviceCalendarPlugin {
  DeviceCalendarPlugin._(); // Prevent instantiation

  /// Returns the platform version (e.g., "Android 13", "iOS 17.0").
  static Future<String?> getPlatformVersion() {
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
  /// final status = await DeviceCalendar.requestPermissions();
  /// if (status == CalendarPermissionStatus.granted) {
  ///   // Access calendars
  /// } else if (status == CalendarPermissionStatus.denied) {
  ///   // Show "Enable in Settings" message
  /// } else if (status == CalendarPermissionStatus.restricted) {
  ///   // Show "Contact administrator" message
  /// }
  /// ```
  static Future<CalendarPermissionStatus> requestPermissions() async {
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
  /// final calendars = await DeviceCalendarPlugin.listCalendars();
  /// for (final calendar in calendars) {
  ///   print('${calendar.name} (${calendar.id})');
  ///   print('  Read-only: ${calendar.readOnly}');
  ///   print('  Primary: ${calendar.isPrimary}');
  ///   print('  Color: ${calendar.colorHex}');
  /// }
  /// ```
  static Future<List<Calendar>> listCalendars() async {
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
  /// final now = DateTime.now();
  /// final nextMonth = now.add(Duration(days: 30));
  ///
  /// // Get all events in the next month
  /// final events = await DeviceCalendarPlugin.retrieveEvents(
  ///   now,
  ///   nextMonth,
  /// );
  ///
  /// // Get events from specific calendars only
  /// final workEvents = await DeviceCalendarPlugin.retrieveEvents(
  ///   now,
  ///   nextMonth,
  ///   calendarIds: ['work-calendar-id', 'project-calendar-id'],
  /// );
  ///
  /// for (final event in events) {
  ///   print('${event.title} at ${event.startDate}');
  /// }
  /// ```
  static Future<List<Event>> retrieveEvents(
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

  /// Retrieves a single event by ID.
  ///
  /// [eventId] is required and identifies the event to retrieve.
  ///
  /// [occurrenceDate] is optional and used to identify a specific instance
  /// of a recurring event. If provided, this method will:
  /// - Query events within ±24 hours of the specified date
  /// - Find the instance whose start date is closest to [occurrenceDate]
  /// - Return that specific instance
  ///
  /// If [occurrenceDate] is null:
  /// - For non-recurring events: Returns the event
  /// - For recurring events: Returns the master event definition with the
  ///   original start/end dates and recurrence rule information
  ///
  /// Returns null if no matching event is found.
  ///
  /// Example:
  /// ```dart
  /// // Get a non-recurring event
  /// final event = await DeviceCalendarPlugin.getEvent('event-123');
  ///
  /// // Get a specific instance of a recurring event
  /// final instance = await DeviceCalendarPlugin.getEvent(
  ///   'recurring-event-456',
  ///   occurrenceDate: DateTime(2025, 11, 15),
  /// );
  /// ```
  static Future<Event?> getEvent(
    String eventId, {
    DateTime? occurrenceDate,
  }) async {
    try {
      if (occurrenceDate != null) {
        // Query ±24 hours around the occurrence date
        final startDate = occurrenceDate.subtract(const Duration(hours: 24));
        final endDate = occurrenceDate.add(const Duration(hours: 24));

        // Use existing retrieveEvents to get all events in that range
        final events = await retrieveEvents(startDate, endDate);

        // Filter by eventId
        final matchingEvents =
            events.where((event) => event.eventId == eventId).toList();

        if (matchingEvents.isEmpty) {
          return null;
        }

        // Find the event with start date closest to occurrenceDate
        Event? closestEvent;
        Duration? closestDifference;

        for (final event in matchingEvents) {
          final difference = event.startDate.difference(occurrenceDate).abs();
          if (closestDifference == null || difference < closestDifference) {
            closestEvent = event;
            closestDifference = difference;
          }
        }

        return closestEvent;
      } else {
        // Get master event directly from platform
        final Map<String, dynamic>? rawEvent =
            await DeviceCalendarPlusPlatform.instance.getEvent(
          eventId,
          null,
        );

        if (rawEvent == null) {
          return null;
        }

        return Event.fromMap(rawEvent);
      }
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
