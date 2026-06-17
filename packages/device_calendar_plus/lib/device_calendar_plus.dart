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

  AutoPermissionMode? _autoPermissions;

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
  AutoPermissionMode? get autoPermissions => _autoPermissions;

  set autoPermissions(AutoPermissionMode? mode) {
    _autoPermissions = mode;
    // A fresh configuration resets the once-per-run prompt budget.
    _autoRequestedTiers.clear();
  }

  /// Access levels already auto-requested this run. Auto-mode prompts at most
  /// once per level: Android folds a declined prompt back into notDetermined, so
  /// without this a decline would re-prompt on every later call. Reset whenever
  /// [autoPermissions] is set.
  final Set<CalendarAccessLevel> _autoRequestedTiers = {};

  /// Requests calendar permission, showing the system dialog on first use.
  ///
  /// [level] chooses how much to ask for: [CalendarAccessLevel.full] (the
  /// default, read and write) or [CalendarAccessLevel.writeOnly] (the gentler
  /// add-only tier, for apps that only create events — a grant returns
  /// [CalendarPermissionStatus.writeOnly]).
  ///
  /// Requesting a tier you already hold returns immediately without prompting.
  /// Requesting [CalendarAccessLevel.full] while holding only write-only
  /// upgrades the app in-app.
  ///
  /// See [doc/permissions.md](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/permissions.md).
  Future<CalendarPermissionStatus> requestPermissions({
    CalendarAccessLevel level = CalendarAccessLevel.full,
  }) async {
    return _handlePermissionRequest(
      () => DeviceCalendarPlusPlatform.instance.requestPermissions(
        level == CalendarAccessLevel.writeOnly,
      ),
    );
  }

  /// Returns the current [CalendarPermissionStatus] without prompting.
  ///
  /// Unlike [requestPermissions], this never shows the system dialog — use it to
  /// decide whether to prompt.
  Future<CalendarPermissionStatus> hasPermissions() async {
    return _handlePermissionRequest(
      () => DeviceCalendarPlusPlatform.instance.hasPermissions(),
    );
  }

  /// Opens the app's settings page, so the user can enable calendar access
  /// after a denial.
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
  /// Only a [CalendarPermissionStatus.notDetermined] status triggers a prompt,
  /// and at most once per access level per run; a tier already held is never
  /// silently escalated. Throws [DeviceCalendarException]
  /// ([DeviceCalendarError.permissionDenied]) when the resulting access does not
  /// satisfy [requiredTier].
  Future<void> _ensurePermission(CalendarAccessLevel requiredTier) async {
    final mode = autoPermissions;
    if (mode == null) return;

    final tierToRequest = mode == AutoPermissionMode.full
        ? CalendarAccessLevel.full
        : requiredTier;

    var status = await hasPermissions();
    // Prompt only on a fresh notDetermined status, and only the first time this
    // run for a given tier. Android folds a soft-deny back into notDetermined,
    // so without the budget a declined prompt would re-fire on every later call.
    // This makes "prompts on first use" literally true and matches iOS, where a
    // decline becomes a terminal denied we never re-prompt.
    if (status == CalendarPermissionStatus.notDetermined &&
        _autoRequestedTiers.add(tierToRequest)) {
      status = await requestPermissions(level: tierToRequest);
    }

    if (!_satisfies(status, requiredTier)) {
      throw DeviceCalendarException(
        errorCode: DeviceCalendarError.permissionDenied,
        message: 'Calendar access required for this operation was not granted '
            '(autoPermissions: ${mode.name}, status: ${status.name}).',
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

  /// Lists all calendars on the device. Requires full access.
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

  /// Lists the accounts (iCloud, Google, local…) that calendars can be created
  /// under. Pass a source to [createCalendar] via [CreateCalendarOptionsIos] or
  /// [CreateCalendarOptionsAndroid] to target a specific account.
  ///
  /// On Android, only sources that already have a calendar are returned.
  /// Requires full access.
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

  /// Creates a calendar and returns its ID.
  ///
  /// [colorHex] is an optional `#RRGGBB` color. [platformOptions] targets a
  /// specific account (see [listSources]); without it a sensible default
  /// account is chosen. Requires full access.
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

  /// Updates a calendar's [name] and/or [colorHex] (`#RRGGBB`).
  ///
  /// Passing neither is a no-op. Requires full access.
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

  /// Deletes a calendar and all of its events. Requires full access.
  ///
  /// Throws [DeviceCalendarException] ([DeviceCalendarError.readOnly]) for a
  /// calendar that can't be deleted (e.g. a system-managed account calendar).
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

  /// Lists events overlapping the half-open range `[startDate, endDate)`, sorted
  /// by start date. An event starting exactly at [endDate] is excluded. Ranges
  /// longer than 4 years are supported.
  ///
  /// [calendarIds] filters to specific calendars; null or empty means all.
  ///
  /// Recurring events are expanded into one [Event] per occurrence — each shares
  /// the series' [Event.eventId] but carries a distinct [Event.instanceId] (see
  /// [getEvent]). Requires full access.
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

  /// Retrieves a single event by [id], or null if not found.
  ///
  /// A bare event ID returns the master (the series, for a recurring event); an
  /// instance ID (`eventId@timestamp`) returns a single occurrence. The instance
  /// ID is unstable — it changes if the occurrence moves — so re-fetch after
  /// edits. Requires full access.
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

  /// Shows an event in the OS's native calendar screen, completing when it's
  /// dismissed. Any edits the user makes are saved by the OS; this does not
  /// report back what changed.
  ///
  /// [id] may be a bare event ID (the series master) or an instance ID (one
  /// occurrence). [edit] only controls whether the modal *starts* in the editor
  /// — the view screen is not read-only and always offers an Edit affordance.
  ///
  /// On Android, `edit: true` is honored inconsistently (Google Calendar opens a
  /// blank new-event editor instead); prefer the view modal and let the user tap
  /// Edit. See [doc/native-ui.md](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/native-ui.md).
  /// Requires full access.
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

  /// Creates an event and returns its ID. Works with write-only access or full.
  ///
  /// Omit [calendarId] (or pass `null`) to write to the device's default
  /// calendar; on Android resolving that default reads the calendar list, so it
  /// needs full access. A non-null but empty ID is an error, as is an [endDate]
  /// before [startDate].
  ///
  /// [recurrenceRule] makes the event recurring (see
  /// [doc/recurring-events.md](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/recurring-events.md)).
  /// [reminders] are lead times **before** start; each is minute-granular and
  /// must be non-negative (see
  /// [doc/reminders.md](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/reminders.md)).
  Future<String> createEvent({
    String? calendarId,
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
    List<Duration>? reminders,
  }) async {
    // Validate fields. A null calendarId is valid (use the default calendar);
    // an explicit but empty/whitespace ID targets nothing — a programmer error.
    if (calendarId != null && calendarId.trim().isEmpty) {
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

    // Convert reminders to whole minutes before start (the wire format).
    final reminderMinutes = _remindersToMinutes(reminders);

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
        reminderMinutes,
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

  /// Deletes an event. A bare event ID deletes the event (the whole series, if
  /// recurring); an instance ID removes only that occurrence.
  ///
  /// To truncate a series from a split point forward, use [deleteRecurring].
  /// Requires full access.
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

  /// Updates an event. A bare [eventId] updates the event (the whole series, if
  /// recurring); an instance ID detaches and edits one occurrence (its
  /// [startDate]/[endDate] are absolute, so it can move to another day).
  ///
  /// To change a property across a series or from a split point forward, use
  /// [updateRecurring].
  ///
  /// Only the fields you pass change. [description], [location], [url], and
  /// [reminders] take a [Patch] — omit to leave unchanged, [Patch.set] to
  /// assign, [Patch.clear] to remove. Setting [timeZone] reinterprets the
  /// wall-clock time rather than preserving the instant. Passing no fields is a
  /// no-op. Requires full access.
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
    Patch<List<Duration>>? reminders,
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
        availability == null &&
        reminders == null) {
      return;
    }

    // Map the typed reminders Patch to the minutes wire format. Validation
    // (negative durations) happens inside _remindersToMinutes.
    final Patch<List<int>>? reminderMinutes = switch (reminders) {
      null => null,
      PatchSet(:final value) => Patch.set(_remindersToMinutes(value)!),
      PatchClear() => const Patch.clear(),
    };

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
        reminders: reminderMinutes,
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

  /// Edits a recurring **series** — its [recurrenceRule], its time-of-day or
  /// [duration], or any field across occurrences. To edit one occurrence, pass
  /// its instance ID to [updateEvent] instead.
  ///
  /// [span] chooses the scope:
  /// - [EventSpan.allEvents] — the whole series follows the change.
  /// - [EventSpan.thisAndFollowing] — splits the series at the occurrence; that
  ///   one and every later one carry the change. Requires [instanceId] to carry
  ///   an occurrence timestamp (a bare event ID throws [ArgumentError]).
  ///
  /// [start] moves the anchor and translates the scope by the same wall-clock
  /// delta — changing day and time together, measured in the event's timezone
  /// (so DST-safe). [duration] must be non-negative whole minutes (whole days
  /// for all-day events). [recurrenceRule] takes a [Patch]: [Patch.set] to
  /// change the rule, [Patch.clear] to stop recurring.
  ///
  /// Moving the day of a rule that pins it explicitly (e.g.
  /// `WeeklyRecurrence(daysOfWeek: …)`) without also passing a [recurrenceRule]
  /// throws [DeviceCalendarException] ([DeviceCalendarError.invalidArguments]),
  /// because the result is ambiguous. Implicit rules and time-only changes
  /// follow the anchor freely. See
  /// [doc/recurring-events.md](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/recurring-events.md).
  ///
  /// Returns the affected scope's event ID (the same ID for `allEvents`, the new
  /// series' ID for `thisAndFollowing`). Passing no fields is a no-op. Requires
  /// full access.
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

  /// Deletes a recurring **series** by [span]:
  /// - [EventSpan.allEvents] — deletes the whole series (same as [deleteEvent]
  ///   with a bare event ID).
  /// - [EventSpan.thisAndFollowing] — removes the occurrence and every later
  ///   one, truncating the series. Requires [instanceId] to carry an occurrence
  ///   timestamp (a bare event ID throws [ArgumentError]).
  ///
  /// To delete one occurrence, pass its instance ID to [deleteEvent]. Requires
  /// full access.
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

  /// Opens the OS's native event editor in create mode, completing when it's
  /// dismissed.
  ///
  /// All parameters are optional pre-fill values; the user can change anything
  /// before saving or cancelling. Useful for letting the user review, or to add
  /// attendees (which can't be done programmatically). Works with write-only
  /// access or full.
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

  /// Normalizes reminder [Duration]s to the whole-minutes-before-start wire
  /// format (the canonical conversion, shared by both platforms).
  ///
  /// Each [Duration] is lead time before the event start, so a non-negative
  /// value is required — a negative [Duration] (after-start) has no valid
  /// interpretation and throws [ArgumentError]; zero (at start) is allowed.
  /// Sub-minute values round to the nearest minute. Duplicate minute values are
  /// de-duplicated to avoid redundant alarm rows, preserving first-seen order.
  /// Returns `null` for a `null` input (no reminders).
  static List<int>? _remindersToMinutes(List<Duration>? reminders) {
    if (reminders == null) return null;
    final seen = <int>{};
    final minutes = <int>[];
    for (final reminder in reminders) {
      if (reminder < Duration.zero) {
        throw ArgumentError.value(
          reminder,
          'reminders',
          'A reminder offset cannot be negative (reminders fire before start)',
        );
      }
      final value = (reminder.inSeconds / 60).round();
      if (seen.add(value)) minutes.add(value);
    }
    return minutes;
  }
}
