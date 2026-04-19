import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';

import 'src/calendar.dart';
import 'src/calendar_permission_status.dart';
import 'src/calendar_source.dart';
import 'src/event.dart';
import 'src/event_availability.dart';
import 'src/platform_exception_converter.dart';
import 'src/recurrence_rule.dart';

export 'package:device_calendar_plus_android/device_calendar_plus_android.dart'
    show CreateCalendarOptionsAndroid;
export 'package:device_calendar_plus_ios/device_calendar_plus_ios.dart'
    show CreateCalendarOptionsIos;
// Platform-specific options
export 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart'
    show CreateCalendarPlatformOptions, InstanceIdParser, ParsedInstanceId;

export 'src/attendee.dart';
export 'src/calendar.dart';
export 'src/calendar_source.dart';
export 'src/calendar_permission_status.dart';
export 'src/device_calendar_error.dart';
export 'src/event.dart';
export 'src/event_availability.dart';
export 'src/event_status.dart';
export 'src/platform_exception_codes.dart';
export 'src/recurrence_rule.dart';

/// Main API for accessing device calendar functionality.
class DeviceCalendar {
  DeviceCalendar._internal();

  static final DeviceCalendar instance = DeviceCalendar._internal();

  factory DeviceCalendar() => instance;

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

  /// Opens the app's settings page in the system settings.
  ///
  /// This is useful when permissions have been denied and you want to guide
  /// the user to manually enable calendar permissions in the system settings.
  ///
  /// On iOS, this opens the app's specific settings page directly.
  /// On Android, this opens the app info page where users can navigate to permissions.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// final status = await plugin.hasPermissions();
  /// if (status == CalendarPermissionStatus.denied) {
  ///   // Show dialog explaining why permission is needed
  ///   showDialog(
  ///     context: context,
  ///     builder: (context) => AlertDialog(
  ///       title: Text('Calendar Permission Required'),
  ///       content: Text('Please enable calendar access in settings.'),
  ///       actions: [
  ///         TextButton(
  ///           onPressed: () {
  ///             Navigator.pop(context);
  ///             plugin.openAppSettings();
  ///           },
  ///           child: Text('Open Settings'),
  ///         ),
  ///       ],
  ///     ),
  ///   );
  /// }
  /// ```
  Future<void> openAppSettings() async {
    try {
      await DeviceCalendarPlusPlatform.instance.openAppSettings();
    } on PlatformException catch (e, stackTrace) {
      final convertedException =
          PlatformExceptionConverter.convertPlatformException(e);
      if (convertedException != null) {
        Error.throwWithStackTrace(convertedException, stackTrace);
      }
      rethrow;
    }
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

  /// Lists available calendar sources/accounts on the device.
  ///
  /// Returns the sources that calendars can be created under. Use a source's
  /// [CalendarSource.id] with [CreateCalendarOptionsIos], or
  /// [CalendarSource.accountName] + [CalendarSource.accountType] with
  /// [CreateCalendarOptionsAndroid] to create calendars under a specific account.
  ///
  /// **Note:** On Android, only sources that already have calendars are returned.
  /// A freshly-added account with no calendars will not appear until its first
  /// calendar is created.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// final sources = await plugin.listSources();
  /// for (final source in sources) {
  ///   print('${source.accountName} (${source.type})');
  /// }
  /// ```
  Future<List<CalendarSource>> listSources() async {
    try {
      final List<Map<String, dynamic>> rawSources =
          await DeviceCalendarPlusPlatform.instance.listSources();
      return rawSources.map((map) => CalendarSource.fromMap(map)).toList();
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
  /// [platformOptions] is an optional platform-specific options object.
  ///
  /// Returns the ID of the newly created calendar.
  ///
  /// The calendar is created in the device's local storage by default.
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
  ///
  /// // Android: Create a calendar with a custom account name
  /// final androidCalendarId = await plugin.createCalendar(
  ///   name: 'My App Calendar',
  ///   platformOptions: CreateCalendarOptionsAndroid(accountName: 'MyApp'),
  /// );
  /// ```
  Future<String> createCalendar({
    required String name,
    String? colorHex,
    CreateCalendarPlatformOptions? platformOptions,
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
          .createCalendar(name, colorHex, platformOptions);
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

  /// Retrieves a single event by ID.
  ///
  /// The [id] can be either an event ID or an instance ID:
  /// - **Event ID**: Returns the master event definition (for recurring events)
  /// - **Instance ID**: Returns a specific occurrence (for recurring events)
  ///
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
  Future<Event?> getEvent(String id) async {
    try {
      // Parse the ID to extract eventId and optional timestamp
      final parsed = InstanceIdParser.parse(id);

      final Map<String, dynamic>? rawEvent =
          await DeviceCalendarPlusPlatform.instance.getEvent(
        parsed.eventId,
        parsed.timestamp,
      );

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
  /// The [id] can be either an event ID or an instance ID:
  /// - **Event ID**: Shows the master event definition (for recurring events)
  /// - **Instance ID**: Shows a specific occurrence (for recurring events)
  ///
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
  Future<void> showEventModal(String id) async {
    try {
      // Parse the ID to extract eventId and optional timestamp
      final parsed = InstanceIdParser.parse(id);

      await DeviceCalendarPlusPlatform.instance.showEventModal(
        parsed.eventId,
        parsed.timestamp,
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
  /// [availability] is the availability status (default: EventAvailability.busy).
  /// [recurrenceRule] is an optional recurrence rule for repeating events.
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
  /// // Create a recurring event
  /// final recurringId = await plugin.createEvent(
  ///   calendarId: 'cal-123',
  ///   title: 'Daily Standup',
  ///   startDate: DateTime(2024, 3, 15, 9, 0),
  ///   endDate: DateTime(2024, 3, 15, 9, 15),
  ///   recurrenceRule: DailyRecurrence(end: CountEnd(30)),
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
    RecurrenceRule? recurrenceRule,
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
    final normalizedStartDate = isAllDay ? _stripTime(startDate) : startDate;
    final normalizedEndDate = isAllDay ? _stripTime(endDate) : endDate;

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
        recurrenceRule?.toRruleString(),
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
  /// [eventId] identifies the event to delete. You can pass either:
  /// - An event ID (e.g., from `event.eventId`)
  /// - An instance ID (e.g., from `event.instanceId`) - the event ID will be extracted
  ///
  /// **For recurring events**: This will delete the ENTIRE series (all past
  /// and future occurrences). Single-instance deletion is not supported to
  /// maintain consistent behavior across platforms.
  ///
  /// For non-recurring events, this deletes the single event.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Delete using event ID
  /// await plugin.deleteEvent(eventId: event.eventId);
  ///
  /// // Delete using instance ID (event ID will be extracted)
  /// await plugin.deleteEvent(eventId: event.instanceId);
  /// ```
  // TODO(breaking): rename param to `id` and stop discarding the parsed
  // timestamp so per-instance delete works (matching getEvent/showEventModal).
  Future<void> deleteEvent({required String eventId}) async {
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Event ID cannot be empty',
      );
    }

    try {
      // Parse the ID to extract eventId (timestamp is ignored for delete)
      final parsed = InstanceIdParser.parse(eventId);

      await DeviceCalendarPlusPlatform.instance.deleteEvent(parsed.eventId);
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
  /// [eventId] identifies the event to update (required). You can pass either:
  /// - An event ID (e.g., from `event.eventId`)
  /// - An instance ID (e.g., from `event.instanceId`) - the event ID will be extracted by the platform
  ///
  /// **For recurring events**: This will update the ENTIRE series (all past
  /// and future occurrences). Single-instance updates are not supported to
  /// maintain consistent behavior across platforms.
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
  /// - [availability] - new availability status
  ///
  /// At least one field must be provided.
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Update event title using event ID (entire series for recurring events)
  /// await plugin.updateEvent(
  ///   eventId: event.eventId,
  ///   title: 'Updated Meeting Title',
  /// );
  ///
  /// // Update using instance ID (event ID will be extracted by platform)
  /// await plugin.updateEvent(
  ///   eventId: event.instanceId,
  ///   isAllDay: true,
  /// );
  ///
  /// // Update multiple fields
  /// await plugin.updateEvent(
  ///   eventId: event.eventId,
  ///   title: 'Team Sync',
  ///   startDate: DateTime(2024, 3, 20, 10, 0),
  ///   endDate: DateTime(2024, 3, 20, 11, 0),
  ///   location: 'Conference Room B',
  ///   availability: EventAvailability.free,
  /// );
  /// ```
  // TODO(breaking): rename param to `id` and stop discarding the parsed
  // timestamp so per-instance update works (matching getEvent/showEventModal).
  Future<void> updateEvent({
    required String eventId,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
    EventAvailability? availability,
  }) async {
    // Validate eventId
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Event ID cannot be empty',
      );
    }

    // Validate at least one field is provided
    if (title == null &&
        startDate == null &&
        endDate == null &&
        description == null &&
        location == null &&
        isAllDay == null &&
        timeZone == null &&
        availability == null) {
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
    final normalizedStartDate = (isAllDay == true && startDate != null)
        ? _stripTime(startDate)
        : startDate;
    final normalizedEndDate =
        (isAllDay == true && endDate != null) ? _stripTime(endDate) : endDate;

    try {
      // Parse the ID to extract eventId (timestamp is ignored for update)
      final parsed = InstanceIdParser.parse(eventId);

      await DeviceCalendarPlusPlatform.instance.updateEvent(
        parsed.eventId,
        title: title,
        startDate: normalizedStartDate,
        endDate: normalizedEndDate,
        description: description,
        location: location,
        isAllDay: isAllDay,
        timeZone: timeZone,
        availability: availability?.name,
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

  /// Opens the native platform calendar editor in create mode.
  ///
  /// All parameters are optional pre-fill values. The native editor opens
  /// with these fields populated (or blank if not provided). The user can
  /// modify any field before saving or cancelling.
  ///
  /// The returned [Future] completes when the modal is dismissed (whether
  /// the user saved or cancelled).
  ///
  /// If [isAllDay] is true, any provided dates are normalized to midnight.
  /// If neither date is provided, the native editor uses its own defaults.
  ///
  /// **Platform APIs:**
  /// - **iOS**: `EKEventEditViewController`
  /// - **Android**: `Intent.ACTION_INSERT`
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Open blank editor
  /// await plugin.showCreateEventModal();
  ///
  /// // Open with pre-filled data
  /// await plugin.showCreateEventModal(
  ///   title: 'Team Meeting',
  ///   startDate: DateTime.now().add(Duration(hours: 1)),
  ///   endDate: DateTime.now().add(Duration(hours: 2)),
  ///   location: 'Conference Room A',
  /// );
  /// ```
  Future<void> showCreateEventModal({
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    RecurrenceRule? recurrenceRule,
    EventAvailability? availability,
  }) async {
    // Validate dates if both are provided
    if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
      throw ArgumentError('End date must be after start date');
    }

    // Normalize dates for all-day events
    final normalizedStart = (isAllDay == true && startDate != null)
        ? _stripTime(startDate)
        : startDate;
    final normalizedEnd =
        (isAllDay == true && endDate != null) ? _stripTime(endDate) : endDate;

    try {
      await DeviceCalendarPlusPlatform.instance.showCreateEventModal(
        title: title,
        startDate: normalizedStart?.millisecondsSinceEpoch,
        endDate: normalizedEnd?.millisecondsSinceEpoch,
        description: description,
        location: location,
        isAllDay: isAllDay,
        recurrenceRule: recurrenceRule?.toRruleString(),
        availability: availability?.name,
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

  /// Strips time components from a DateTime, returning midnight of the same day.
  static DateTime _stripTime(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);
}
