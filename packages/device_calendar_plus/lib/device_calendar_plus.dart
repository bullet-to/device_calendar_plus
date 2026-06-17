import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';

import 'src/auto_permission_mode.dart';
import 'src/calendar.dart';
import 'src/calendar_access_level.dart';
import 'src/calendar_permission_status.dart';
import 'src/calendar_source.dart';
import 'src/device_calendar_error.dart';
import 'src/event.dart';
import 'src/event_availability.dart';
import 'src/event_span.dart';
import 'src/platform_exception_converter.dart';
import 'src/recurrence_rule.dart';

export 'package:device_calendar_plus_android/device_calendar_plus_android.dart'
    show CreateCalendarOptionsAndroid;
export 'package:device_calendar_plus_ios/device_calendar_plus_ios.dart'
    show CreateCalendarOptionsIos;
// Platform-specific options
export 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart'
    show
        CreateCalendarPlatformOptions,
        InstanceIdParser,
        ParsedInstanceId,
        Patch,
        PatchSet,
        PatchClear;

export 'src/attendee.dart';
export 'src/auto_permission_mode.dart';
export 'src/calendar.dart';
export 'src/calendar_access_level.dart';
export 'src/calendar_source.dart';
export 'src/calendar_permission_status.dart';
export 'src/device_calendar_error.dart';
export 'src/event.dart';
export 'src/event_availability.dart';
export 'src/event_status.dart';
export 'src/event_span.dart';
export 'src/platform_exception_codes.dart';
export 'src/recurrence_rule.dart';

/// Main API for accessing device calendar functionality.
class DeviceCalendar {
  DeviceCalendar._internal();

  static final DeviceCalendar instance = DeviceCalendar._internal();

  factory DeviceCalendar() => instance;

  /// Opts methods into requesting calendar permission automatically.
  ///
  /// When `null` (the default) nothing changes — methods never prompt on their
  /// own and you call [requestPermissions] yourself. When set to an
  /// [AutoPermissionMode], each method ensures the access it needs before
  /// touching the platform: it requests permission once when the status is
  /// [CalendarPermissionStatus.notDetermined], and throws a
  /// [DeviceCalendarException] with [DeviceCalendarError.permissionDenied] if
  /// access is not granted.
  ///
  /// Set this once, typically at app start:
  /// ```dart
  /// DeviceCalendar.instance.autoPermissions = AutoPermissionMode.asNeeded;
  /// ```
  AutoPermissionMode? autoPermissions;

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// [level] chooses how much access to ask for:
  /// - [CalendarAccessLevel.full] (the default) — full read and write access.
  /// - [CalendarAccessLevel.writeOnly] — the gentler add-only prompt, for apps
  ///   that only create events and never read existing calendar data. A
  ///   granted write-only request returns [CalendarPermissionStatus.writeOnly].
  ///   On iOS 16 and below write-only does not exist, so this falls back to a
  ///   full-access request and a grant returns
  ///   [CalendarPermissionStatus.granted].
  ///
  /// If you already hold a tier that satisfies the request, this returns
  /// immediately without prompting (full access satisfies a write-only ask).
  /// Requesting [CalendarAccessLevel.full] while only write-only is held
  /// upgrades the app on both platforms — only the prompt differs:
  /// - **Android**: `READ_CALENDAR` and `WRITE_CALENDAR` belong to the same
  ///   `CALENDAR` permission group, so once write-only has granted
  ///   `WRITE_CALENDAR` the OS grants the read upgrade **immediately, with no
  ///   dialog**, and this returns [CalendarPermissionStatus.granted].
  /// - **iOS**: re-presents the system dialog, this time asking for full
  ///   access. If the user agrees this returns [CalendarPermissionStatus.granted];
  ///   if they decline it returns the still-held
  ///   [CalendarPermissionStatus.writeOnly].
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
  ///
  /// // Add-only app: ask for the gentler write-only prompt.
  /// final writeStatus = await plugin.requestPermissions(
  ///   level: CalendarAccessLevel.writeOnly,
  /// );
  /// ```
  Future<CalendarPermissionStatus> requestPermissions({
    CalendarAccessLevel level = CalendarAccessLevel.full,
  }) async {
    return _handlePermissionRequest(
      () => DeviceCalendarPlusPlatform.instance.requestPermissions(
        level == CalendarAccessLevel.writeOnly,
      ),
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

  /// Ensures the access an operation needs is held, requesting it when
  /// [autoPermissions] is set. A no-op in manual mode (`autoPermissions ==
  /// null`).
  ///
  /// [requiredTier] is the minimum access the calling operation needs:
  /// [CalendarAccessLevel.writeOnly] for add-only operations, otherwise
  /// [CalendarAccessLevel.full]. In [AutoPermissionMode.full] every request is
  /// upgraded to full regardless of [requiredTier].
  ///
  /// Only a [CalendarPermissionStatus.notDetermined] status triggers a prompt;
  /// a tier already held is never silently escalated. Throws
  /// [DeviceCalendarException] ([DeviceCalendarError.permissionDenied]) when the
  /// resulting access does not satisfy [requiredTier].
  Future<void> _ensurePermission(CalendarAccessLevel requiredTier) async {
    final mode = autoPermissions;
    if (mode == null) return;

    var status = await hasPermissions();
    if (status == CalendarPermissionStatus.notDetermined) {
      status = await requestPermissions(
        level: mode == AutoPermissionMode.full
            ? CalendarAccessLevel.full
            : requiredTier,
      );
    }

    if (!_satisfies(status, requiredTier)) {
      throw DeviceCalendarException(
        errorCode: DeviceCalendarError.permissionDenied,
        message: 'Calendar access required for this operation was not granted '
            '(autoPermissions: ${mode.name}).',
      );
    }
  }

  /// Whether [status] grants enough access for [tier]. Full access satisfies
  /// any tier; write-only satisfies only a write-only requirement.
  bool _satisfies(CalendarPermissionStatus status, CalendarAccessLevel tier) {
    if (status == CalendarPermissionStatus.granted) return true;
    if (status == CalendarPermissionStatus.writeOnly) {
      return tier == CalendarAccessLevel.writeOnly;
    }
    return false;
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
    await _ensurePermission(CalendarAccessLevel.full);
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
    await _ensurePermission(CalendarAccessLevel.full);
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

    await _ensurePermission(CalendarAccessLevel.full);
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
  /// Passing neither [name] nor [colorHex] is a no-op (nothing to change).
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
    // Validate calendarId — an empty id targets no calendar (matches the
    // empty-id guards on updateEvent/updateRecurring).
    if (calendarId.trim().isEmpty) {
      throw ArgumentError.value(
        calendarId,
        'calendarId',
        'Calendar ID cannot be empty',
      );
    }

    // No changed fields is a valid no-op: nothing to write, so return without
    // a platform call.
    if (name == null && colorHex == null) {
      return;
    }

    // Validate name if provided
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Calendar name cannot be empty',
      );
    }

    await _ensurePermission(CalendarAccessLevel.full);
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
    await _ensurePermission(CalendarAccessLevel.full);
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
  /// [startDate] and [endDate] define a half-open interval `[start, end)` —
  /// events that overlap this range are returned, but an event starting
  /// exactly at [endDate] is excluded.
  ///
  /// Ranges longer than 4 years are supported. iOS's underlying query caps a
  /// single span at ~4 years, so wide ranges are transparently split into
  /// smaller windows and merged — every event in the range is returned once.
  ///
  /// [calendarIds] is an optional parameter to filter events to specific
  /// calendars. If null or empty, events from all calendars are returned.
  ///
  /// Recurring events are automatically expanded into individual instances
  /// within the date range — you get one [Event] per occurrence, not a single
  /// master. Each instance has:
  /// - The same [Event.eventId] (shared by the whole series)
  /// - Different [Event.startDate] and [Event.endDate]
  /// - A distinct [Event.instanceId] (format `eventId@timestamp`) that pins
  ///   the occurrence
  ///
  /// Pass that [Event.instanceId] to [getEvent], [updateEvent], [deleteEvent],
  /// or [showEventModal] to act on a single occurrence. (For non-recurring
  /// events `instanceId == eventId`.) The id is plugin-derived and unstable —
  /// it changes if the occurrence's start date moves, so re-fetch after edits.
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
    await _ensurePermission(CalendarAccessLevel.full);
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
    await _ensurePermission(CalendarAccessLevel.full);
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
  /// When [edit] is `true`, opens the native editor directly. When `false`
  /// (the default), opens the native view screen — but note this is **not
  /// read-only**: on both platforms the native screen exposes an Edit affordance
  /// that lets the user modify the event from there. `edit` only controls
  /// whether the modal *starts* in the editor; it cannot prevent editing.
  ///
  /// Either way, edits made by the user are saved to the device calendar
  /// directly by the OS. This method completes when the modal is dismissed and
  /// does not report back whether (or what) the user changed.
  ///
  /// **Platform Differences:**
  /// - **iOS**: Presents `EKEventViewController` (view, with `allowsEditing`) or
  ///   `EKEventEditViewController` (edit) in a native modal. Both reliably bind
  ///   to the existing event.
  /// - **Android**: Fires `ACTION_VIEW` or `ACTION_EDIT`; the system calendar
  ///   app renders the screen, and its view screen offers an edit button.
  ///
  ///   **Caveat (`edit: true` on Android):** `ACTION_EDIT` is honored
  ///   inconsistently across calendar apps. Notably, **Google Calendar ignores
  ///   it for an existing event and opens a blank new-event editor instead** —
  ///   the AOSP/stock calendar lands in the editor as expected. There is no
  ///   intent that reliably opens Google Calendar directly into edit mode on an
  ///   existing event. For a dependable "edit this event" flow, use
  ///   `edit: false` (`ACTION_VIEW`) and let the user tap the edit button on the
  ///   details screen. `iOS` is unaffected.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  /// // Open the view screen (the user can still tap Edit from here)
  /// await plugin.showEventModal(event.instanceId);
  ///
  /// // Open directly in the editor
  /// await plugin.showEventModal(event.instanceId, edit: true);
  /// ```
  Future<void> showEventModal(String id, {bool edit = false}) async {
    await _ensurePermission(CalendarAccessLevel.full);
    try {
      final parsed = InstanceIdParser.parse(id);

      await DeviceCalendarPlusPlatform.instance.showEventModal(
        parsed.eventId,
        parsed.timestamp,
        edit: edit,
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
  /// [url] is an optional URL associated with the event. Round-trips through
  ///   [Event.url]. On iOS this maps to `EKEvent.url` (visible in the native
  ///   Calendar UI); on Android it maps to
  ///   `CalendarContract.Events.CUSTOM_APP_URI`.
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
  ///   url: 'https://example.com/meeting/123',
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
    String? url,
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

    await _ensurePermission(CalendarAccessLevel.writeOnly);
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
        url,
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

  /// Deletes a single event or a single occurrence of a recurring event.
  ///
  /// [eventId] identifies what to delete (required):
  /// - **Bare event ID** (e.g., `event.eventId`): deletes the non-recurring
  ///   event, or the master of a recurring series (all occurrences).
  /// - **Instance ID** (e.g., `event.instanceId`, format
  ///   `eventId@timestamp`): removes only that occurrence from the series,
  ///   as a cancelled exception; the rest of the series is untouched.
  ///
  /// To delete an entire recurring series or truncate it from a split point
  /// forward, use [deleteRecurring] instead.
  ///
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Delete a non-recurring event (or a whole recurring series)
  /// await plugin.deleteEvent(eventId: event.eventId);
  ///
  /// // Delete only this one occurrence of a recurring event
  /// await plugin.deleteEvent(eventId: event.instanceId);
  /// ```
  Future<void> deleteEvent({required String eventId}) async {
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Event ID cannot be empty',
      );
    }

    // A bare event ID carries no timestamp and targets the event itself (the
    // whole series when recurring); an instance ID carries the occurrence
    // timestamp, which the platform uses to remove that occurrence alone.
    final parsed = InstanceIdParser.parse(eventId);

    await _ensurePermission(CalendarAccessLevel.full);
    try {
      await DeviceCalendarPlusPlatform.instance.deleteEvent(
        parsed.eventId,
        timestamp: parsed.timestamp,
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

  /// Updates a single event or a single occurrence of a recurring event.
  ///
  /// [eventId] identifies what to update (required):
  /// - **Bare event ID** (e.g., `event.eventId`): updates the non-recurring
  ///   event, or the master of a recurring series (all occurrences).
  /// - **Instance ID** (e.g., `event.instanceId`, format
  ///   `eventId@timestamp`): detaches that single occurrence from the series
  ///   and applies the changes to it alone. [startDate] and [endDate] are
  ///   absolute instants, so the occurrence can move to a different day.
  ///
  /// To change a property across an entire recurring series or from a split
  /// point forward, use [updateRecurring] instead.
  ///
  /// All field parameters are optional - only provided fields will be updated:
  /// - [title] - new event title
  /// - [startDate] - new start date/time
  /// - [endDate] - new end date/time
  /// - [description] - event description ([Patch.set] to change, [Patch.clear]
  ///   to remove)
  /// - [location] - event location ([Patch.set] to change, [Patch.clear] to
  ///   remove)
  /// - [url] - URL associated with the event ([Patch.set] to change,
  ///   [Patch.clear] to remove). Round-trips through [Event.url]. On iOS this
  ///   maps to `EKEvent.url`; on Android it maps to
  ///   `CalendarContract.Events.CUSTOM_APP_URI`.
  /// - [isAllDay] - change between all-day and timed event
  ///   - Changing timed → all-day: Time components are stripped to midnight
  ///   - Changing all-day → timed: Midnight time is used
  /// - [timeZone] - new timezone identifier
  ///   - Note: This reinterprets the local time, not preserving the instant
  ///   - Example: "3:00 PM EST" → "3:00 PM PST" (different instant in time)
  /// - [availability] - new availability status
  ///
  /// [description], [location] and [url] take a [Patch]: omit the argument (or
  /// pass `null`) to leave the field unchanged, [Patch.set] to assign a new
  /// value, [Patch.clear] to remove the existing value.
  ///
  /// Providing no fields is a no-op (nothing to change).
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Update a non-recurring event (or all occurrences of a recurring one)
  /// await plugin.updateEvent(
  ///   eventId: event.eventId,
  ///   title: 'Updated Meeting Title',
  /// );
  ///
  /// // Edit only this one occurrence of a recurring event
  /// await plugin.updateEvent(
  ///   eventId: event.instanceId,
  ///   title: 'Moved this week only',
  ///   startDate: DateTime(2024, 3, 21, 15, 0),
  ///   endDate: DateTime(2024, 3, 21, 16, 0),
  /// );
  /// ```
  Future<void> updateEvent({
    required String eventId,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
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

    // No changed fields is a valid no-op (e.g. the user pressed Save without
    // editing): the event already matches the requested values, so there is
    // nothing to write — return without a platform call.
    if (title == null &&
        startDate == null &&
        endDate == null &&
        description == null &&
        location == null &&
        url == null &&
        isAllDay == null &&
        timeZone == null &&
        availability == null) {
      return;
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

    // A bare event ID carries no timestamp and targets the event itself (the
    // whole series when recurring); an instance ID carries the occurrence
    // timestamp, which the platform uses to detach and edit that occurrence.
    final parsed = InstanceIdParser.parse(eventId);

    await _ensurePermission(CalendarAccessLevel.full);
    try {
      await DeviceCalendarPlusPlatform.instance.updateEvent(
        parsed.eventId,
        timestamp: parsed.timestamp,
        title: title,
        startDate: normalizedStartDate,
        endDate: normalizedEndDate,
        description: description,
        location: location,
        url: url,
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

  /// Updates a recurring event's series, choosing which occurrences the edit
  /// affects.
  ///
  /// Use this instead of [updateEvent] when you need to change a recurring
  /// event's [recurrenceRule], its time-of-day or duration across a series, or
  /// when an edit should split the series at a given point.
  ///
  /// To edit a single occurrence, pass its instance ID to [updateEvent]
  /// instead.
  ///
  /// [instanceId] identifies the occurrence to act on — pass an instance ID
  /// (`event.instanceId`). For [EventSpan.thisAndFollowing] it must carry an
  /// occurrence timestamp (`eventId@timestamp`); a bare event ID throws
  /// [ArgumentError].
  ///
  /// [span] chooses the scope:
  /// - [EventSpan.allEvents] — the whole series follows the change.
  ///   Clearing [recurrenceRule] collapses the series into a single event.
  /// - [EventSpan.thisAndFollowing] — the series is split at the
  ///   occurrence timestamp: that occurrence and every later one carry the
  ///   edit; earlier occurrences are untouched. Clearing [recurrenceRule] here
  ///   turns the occurrence into a standalone non-recurring event and drops
  ///   every later one, leaving the earlier occurrences in the original series
  ///   (the "this and future, made non-recurring" case).
  ///
  /// Time fields:
  /// - [start] moves the anchored occurrence to a new start, and translates
  ///   the whole scope by the same wall-clock delta — so it changes the
  ///   time-of-day **and** the day together. Moving Monday 11 PM to Tuesday
  ///   1 AM shifts every occurrence one day later and to 1 AM. The delta is
  ///   measured against the occurrence the [instanceId] points at (or the
  ///   series anchor, for `allEvents` with a bare event ID), in the event's
  ///   timezone, so it is DST-safe. Duration is preserved unless [duration]
  ///   is also passed. On all-day events only the date moves; the time-of-day
  ///   is ignored.
  /// - [duration] sets the event duration; it must be non-negative (zero is
  ///   allowed for an instantaneous event) and a whole number of minutes. For
  ///   all-day events, only whole-day durations are valid (e.g.,
  ///   `Duration(days: 3)` for a three-day conference).
  ///
  /// [recurrenceRule] takes a [Patch]: omit it to leave recurrence unchanged,
  /// [Patch.set] to change the rule, [Patch.clear] to remove it (the event
  /// stops recurring).
  ///
  /// **[start] moves the series anchor; the recurrence rule is yours.**
  ///
  /// - Rules whose day is *implied by the start* — the defaults
  ///   `WeeklyRecurrence()`, `MonthlyRecurrence()`, `DailyRecurrence()` — have
  ///   no explicit day pinned, so moving the day with [start] is enough: the
  ///   pattern follows the anchor (a Monday-anchored weekly becomes a Tuesday
  ///   one). Nothing else to do.
  /// - Rules that *pin a day explicitly* — `WeeklyRecurrence(daysOfWeek: …)`,
  ///   `MonthlyRecurrence(daysOfMonth: …)`, positional rules like "2nd Tuesday"
  ///   — cannot be moved to a different day by [start] alone. If [start] would
  ///   change the pinned weekday (or day-of-month, or month) and you do **not**
  ///   pass a [recurrenceRule], this throws [DeviceCalendarException] with
  ///   [DeviceCalendarError.invalidArguments]. Pass the new rule in the same
  ///   call to say what the pattern should become.
  ///
  /// *Why throw instead of guessing?* Moving one day of a multi-day rule is
  /// genuinely ambiguous: dragging the Monday of a Mon/Wed/Fri series to
  /// Tuesday could mean Tue/Wed/Fri (that day reassigned) or Tue/Thu/Sat (the
  /// whole pattern shifted) — there is no single right answer, and Google
  /// Calendar itself mishandles it. Silently picking one would surprise half
  /// the callers; silently doing nothing reads as a broken drag and behaves
  /// differently on iOS vs Android. So the API refuses and hands the decision
  /// back to you, who can express it exactly via [recurrenceRule].
  ///
  /// Edge cases that do **not** throw (the day-spec is unchanged):
  /// - changing only the time-of-day, or only [duration];
  /// - a whole-week shift of a weekly rule (e.g. +7 days keeps the weekday);
  /// - any move on an implicit rule (it has no pinned day to contradict).
  ///
  /// Watch for the converse: a **cross-midnight** retime of a pinned series
  /// (11 PM → 1 AM) rolls the date forward a day, so it *does* change the
  /// weekday and will throw — pass a [recurrenceRule] for those too.
  ///
  /// **Secondary effects** — what happens to occurrences the user had
  /// individually customised — are best-effort and differ by platform.
  /// Customisations before a `thisAndFollowing` split point survive.
  /// Customisations after the split point (or anywhere, for `allEvents`) are
  /// reset: a moved occurrence persists as a detached standalone event, and a
  /// deleted occurrence may reappear if the new rule regenerates that date.
  ///
  /// Returns the event ID for the affected scope — the same ID for
  /// `allEvents`, the new series' ID for `thisAndFollowing`.
  ///
  /// Providing no fields is a no-op (nothing to change).
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Move a nightshift series from 11 PM to 1 AM the next day
  /// await plugin.updateRecurring(
  ///   event.instanceId, // an occurrence currently at 11 PM
  ///   EventSpan.allEvents,
  ///   start: DateTime(2024, 3, 19, 1, 0), // the day after, 1 AM
  /// );
  ///
  /// // Change the duration of all occurrences to 90 minutes
  /// await plugin.updateRecurring(
  ///   event.instanceId,
  ///   EventSpan.allEvents,
  ///   duration: Duration(minutes: 90),
  /// );
  ///
  /// // Split: this occurrence and later ones move to a new start
  /// final newSeriesId = await plugin.updateRecurring(
  ///   event.instanceId,
  ///   EventSpan.thisAndFollowing,
  ///   start: DateTime(2024, 3, 18, 15, 0),
  ///   duration: Duration(hours: 1),
  /// );
  ///
  /// // Change the whole series to weekly
  /// await plugin.updateRecurring(
  ///   event.instanceId,
  ///   EventSpan.allEvents,
  ///   recurrenceRule: Patch.set(WeeklyRecurrence(end: CountEnd(10))),
  /// );
  /// ```
  Future<String> updateRecurring(
    String instanceId,
    EventSpan span, {
    String? title,
    DateTime? start,
    Duration? duration,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
    bool? isAllDay,
    String? timeZone,
    EventAvailability? availability,
    Patch<RecurrenceRule>? recurrenceRule,
  }) async {
    // Validate instanceId
    if (instanceId.trim().isEmpty) {
      throw ArgumentError.value(
        instanceId,
        'instanceId',
        'Instance ID cannot be empty',
      );
    }

    // Parse the ID — thisAndFollowing acts on a specific occurrence, so it
    // needs an occurrence timestamp.
    final parsed = InstanceIdParser.parse(instanceId);
    if (span == EventSpan.thisAndFollowing && parsed.timestamp == null) {
      throw ArgumentError.value(
        instanceId,
        'instanceId',
        'EventSpan.thisAndFollowing requires an instance ID with an '
            'occurrence timestamp (eventId@timestamp)',
      );
    }

    // A negative duration is invalid, but zero is allowed: zero-duration
    // (instantaneous) events are supported — createEvent accepts
    // endDate == startDate, and listEvents returns them (#416). The
    // whole-minute check below still applies (0 is a whole minute).
    if (duration != null && duration < Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'duration cannot be negative',
      );
    }
    if (duration != null &&
        duration.inMicroseconds % Duration.microsecondsPerMinute != 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'duration must be a whole number of minutes',
      );
    }

    // [start] is accepted on all-day events too — only its date is used, the
    // time-of-day is ignored at the platform layer (an all-day event has no
    // time-of-day to set). So no startTime/all-day contradiction to reject.

    // All-day events only accept whole-day durations.
    if (isAllDay == true &&
        duration != null &&
        duration.inMicroseconds % Duration.microsecondsPerDay != 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'All-day events require whole-day durations (multiples of 24 hours)',
      );
    }

    // No changed fields is a valid no-op: there is nothing to write, and
    // nothing to split for thisAndFollowing. Return the targeted event id —
    // the scope the caller named, unchanged.
    if (title == null &&
        start == null &&
        duration == null &&
        description == null &&
        location == null &&
        url == null &&
        isAllDay == null &&
        timeZone == null &&
        availability == null &&
        recurrenceRule == null) {
      return parsed.eventId;
    }

    // The platform layer works in RRULE strings; map the typed Patch across.
    final Patch<String>? recurrenceRulePatch = switch (recurrenceRule) {
      null => null,
      PatchSet(:final value) => Patch.set(value.toRruleString()),
      PatchClear() => const Patch.clear(),
    };

    await _ensurePermission(CalendarAccessLevel.full);
    try {
      return await DeviceCalendarPlusPlatform.instance.updateRecurring(
        parsed.eventId,
        parsed.timestamp,
        span.name,
        title: title,
        start: start,
        durationMinutes: duration?.inMinutes,
        description: description,
        location: location,
        url: url,
        isAllDay: isAllDay,
        timeZone: timeZone,
        availability: availability?.name,
        recurrenceRule: recurrenceRulePatch,
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

  /// Deletes a recurring event's series, choosing which occurrences are
  /// removed.
  ///
  /// Use this instead of [deleteEvent] when a recurring series should be
  /// truncated from a split point forward, or deleted outright.
  ///
  /// To delete a single occurrence, pass its instance ID to [deleteEvent]
  /// instead.
  ///
  /// [instanceId] identifies the occurrence to act on — pass an instance ID
  /// (`event.instanceId`). For [EventSpan.thisAndFollowing] it must carry an
  /// occurrence timestamp (`eventId@timestamp`); a bare event ID throws
  /// [ArgumentError].
  ///
  /// [span] chooses the scope:
  /// - [EventSpan.allEvents] — the whole series is deleted (the same result
  ///   as [deleteEvent] with a bare event ID).
  /// - [EventSpan.thisAndFollowing] — the occurrence at the timestamp and
  ///   every later one are removed; the series is truncated to end before it.
  ///   Earlier occurrences are untouched.
  ///
  /// Requires calendar write permissions - call [requestPermissions] first.
  ///
  /// Example:
  /// ```dart
  /// final plugin = DeviceCalendar.instance;
  ///
  /// // Delete the whole series
  /// await plugin.deleteRecurring(event.instanceId, EventSpan.allEvents);
  ///
  /// // Delete this occurrence and every later one
  /// await plugin.deleteRecurring(
  ///   event.instanceId,
  ///   EventSpan.thisAndFollowing,
  /// );
  /// ```
  Future<void> deleteRecurring(String instanceId, EventSpan span) async {
    // Validate instanceId
    if (instanceId.trim().isEmpty) {
      throw ArgumentError.value(
        instanceId,
        'instanceId',
        'Instance ID cannot be empty',
      );
    }

    // Parse the ID — thisAndFollowing acts on a specific occurrence, so it
    // needs an occurrence timestamp.
    final parsed = InstanceIdParser.parse(instanceId);
    if (span == EventSpan.thisAndFollowing && parsed.timestamp == null) {
      throw ArgumentError.value(
        instanceId,
        'instanceId',
        'EventSpan.thisAndFollowing requires an instance ID with an '
            'occurrence timestamp (eventId@timestamp)',
      );
    }

    await _ensurePermission(CalendarAccessLevel.full);
    try {
      await DeviceCalendarPlusPlatform.instance.deleteRecurring(
        parsed.eventId,
        parsed.timestamp,
        span.name,
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

    await _ensurePermission(CalendarAccessLevel.writeOnly);
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
