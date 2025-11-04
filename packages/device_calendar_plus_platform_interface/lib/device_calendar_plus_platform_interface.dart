import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface that implementations of device_calendar_plus must implement.
///
/// Platform implementations should extend this class rather than implement it
/// as `DeviceCalendar`. Extending this class (using `extends`) ensures that
/// the subclass will get the default implementation, while platform
/// implementations that `implements` this interface will be broken by newly
/// added [DeviceCalendarPlusPlatform] methods.
abstract class DeviceCalendarPlusPlatform extends PlatformInterface {
  DeviceCalendarPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceCalendarPlusPlatform? _instance;

  /// The default instance of [DeviceCalendarPlusPlatform] to use.
  ///
  /// Platform-specific implementations (Android/iOS) set this automatically.
  static DeviceCalendarPlusPlatform get instance {
    if (_instance == null) {
      throw StateError(
        'DeviceCalendarPlusPlatform.instance has not been initialized. '
        'This should never happen in production as platform-specific '
        'implementations register themselves automatically.',
      );
    }
    return _instance!;
  }

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [DeviceCalendarPlusPlatform] when they register themselves.
  static set instance(DeviceCalendarPlusPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Returns the platform version.
  Future<String?> getPlatformVersion();

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// Returns the raw integer status code from the platform.
  /// The main API layer converts this to [CalendarPermissionStatus].
  Future<int?> requestPermissions();

  /// Lists all calendars available on the device.
  ///
  /// Returns a list of calendar data as maps. The main API layer
  /// converts these to [DeviceCalendar] objects.
  Future<List<Map<String, dynamic>>> listCalendars();

  /// Creates a new calendar on the device.
  ///
  /// [name] is the display name for the calendar (required).
  /// [colorHex] is an optional color in #RRGGBB format.
  ///
  /// Returns the ID of the newly created calendar.
  ///
  /// The calendar is created in the device's local storage.
  /// Requires calendar write permissions.
  Future<String> createCalendar(String name, String? colorHex);

  /// Updates an existing calendar on the device.
  ///
  /// [calendarId] is the ID of the calendar to update.
  /// [name] is the new display name for the calendar (optional).
  /// [colorHex] is the new color in #RRGGBB format (optional).
  ///
  /// At least one of [name] or [colorHex] must be provided.
  /// Requires calendar write permissions.
  Future<void> updateCalendar(
      String calendarId, String? name, String? colorHex);

  /// Deletes a calendar from the device.
  ///
  /// [calendarId] is the ID of the calendar to delete.
  ///
  /// This will also delete all events within the calendar.
  /// Requires calendar write permissions.
  Future<void> deleteCalendar(String calendarId);

  /// Retrieves events within the specified date range.
  ///
  /// Returns a list of event data as maps. The main API layer
  /// converts these to [Event] objects.
  Future<List<Map<String, dynamic>>> retrieveEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  );

  /// Retrieves a single event by instance ID.
  ///
  /// [instanceId] uniquely identifies the event instance:
  /// - For non-recurring events: Just the eventId
  /// - For recurring events: "eventId@rawTimestampMillis" format
  ///
  /// Returns event data as a map (including instanceId field), or null if not found.
  Future<Map<String, dynamic>?> getEvent(String instanceId);

  /// Shows a calendar event in a modal dialog.
  ///
  /// [instanceId] uniquely identifies the event instance to show:
  /// - For non-recurring events: Just the eventId
  /// - For recurring events: "eventId@rawTimestampMillis" format
  ///
  /// On iOS, presents the event in a modal using EKEventViewController.
  /// On Android, opens the event using an Intent with ACTION_VIEW.
  Future<void> showEvent(String instanceId);

  /// Creates a new event in the specified calendar.
  ///
  /// [calendarId] is the ID of the calendar to create the event in.
  /// [title] is the event title.
  /// [startDate] is the start date/time.
  /// [endDate] is the end date/time.
  /// [isAllDay] indicates if this is an all-day event.
  /// [description] is optional event notes/description.
  /// [location] is optional event location.
  /// [timeZone] is optional timezone identifier (null for all-day events).
  /// [availability] is the availability status (busy, free, tentative, unavailable).
  ///
  /// Returns the ID of the newly created event (system-generated).
  /// Requires calendar write permissions.
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
  );

  /// Deletes an event from the device.
  ///
  /// [instanceId] uniquely identifies the event instance to delete:
  /// - For non-recurring events: Just the eventId
  /// - For recurring events: "eventId@rawTimestampMillis" format
  ///
  /// [deleteAllInstances] determines deletion behavior for recurring events:
  /// - true: Deletes all instances of the recurring event
  /// - false: Deletes only this specific instance
  ///
  /// Requires calendar write permissions.
  Future<void> deleteEvent(String instanceId, bool deleteAllInstances);
}
