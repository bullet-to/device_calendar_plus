import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/create_calendar_options.dart';

export 'src/create_calendar_options.dart';
export 'src/instance_id_parser.dart';

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

  /// Requests calendar permissions from the user.
  ///
  /// On first call, this will show the system permission dialog.
  /// On subsequent calls, it returns the current permission status.
  ///
  /// Returns the raw string status value from the platform.
  /// The main API layer converts this to [CalendarPermissionStatus].
  Future<String?> requestPermissions();

  /// Checks the current calendar permission status WITHOUT requesting permissions.
  ///
  /// Unlike [requestPermissions], this method will NOT prompt the user for
  /// permissions if they haven't been granted yet. It only checks the current status.
  ///
  /// Returns the raw string status value from the platform.
  /// The main API layer converts this to [CalendarPermissionStatus].
  Future<String?> hasPermissions();

  /// Opens the app's settings page in the system settings.
  ///
  /// This is useful when permissions have been denied and you want to guide
  /// the user to manually enable calendar permissions in the system settings.
  ///
  /// On iOS, opens the app's specific settings page.
  /// On Android, opens the app info page where users can navigate to permissions.
  Future<void> openAppSettings();

  /// Lists all calendar sources/accounts available on the device.
  ///
  /// Returns a list of source data as maps. The main API layer
  /// converts these to [CalendarSource] objects.
  ///
  /// On iOS, returns `EKSource` objects from EventKit.
  /// On Android, returns unique account name + account type combinations
  /// from the Calendar Provider.
  Future<List<Map<String, dynamic>>> listSources();

  /// Lists all calendars available on the device.
  ///
  /// Returns a list of calendar data as maps. The main API layer
  /// converts these to [DeviceCalendar] objects.
  Future<List<Map<String, dynamic>>> listCalendars();

  /// Creates a new calendar on the device.
  ///
  /// [name] is the display name for the calendar (required).
  /// [colorHex] is an optional color in #RRGGBB format.
  /// [platformOptions] is an optional platform-specific options object.
  ///
  /// Returns the ID of the newly created calendar.
  ///
  /// The calendar is created in the device's local storage by default.
  /// Platform-specific options can modify this behavior (e.g., Android
  /// allows specifying a custom account name).
  /// Requires calendar write permissions.
  Future<String> createCalendar(
    String name,
    String? colorHex,
    CreateCalendarPlatformOptions? platformOptions,
  );

  /// Updates an existing calendar on the device.
  ///
  /// [calendarId] is the ID of the calendar to update.
  /// [name] is the new display name for the calendar (optional).
  /// [colorHex] is the new color in #RRGGBB format (optional).
  ///
  /// At least one of [name] or [colorHex] must be provided.
  /// Requires calendar write permissions.
  Future<void> updateCalendar(
    String calendarId,
    String? name,
    String? colorHex,
  );

  /// Deletes a calendar from the device.
  ///
  /// [calendarId] is the ID of the calendar to delete.
  ///
  /// This will also delete all events within the calendar.
  /// Requires calendar write permissions.
  Future<void> deleteCalendar(String calendarId);

  /// Lists events within the specified date range.
  ///
  /// Returns a list of event data as maps. The main API layer
  /// converts these to [Event] objects.
  Future<List<Map<String, dynamic>>> listEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  );

  /// Retrieves a single event by event ID and optional timestamp.
  ///
  /// [eventId] is the event identifier.
  /// [timestamp] is the occurrence timestamp in milliseconds for recurring events.
  ///
  /// Returns event data as a map (including instanceId field), or null if not found.
  Future<Map<String, dynamic>?> getEvent(String eventId, int? timestamp);

  /// Shows a calendar event in a modal dialog.
  ///
  /// [eventId] is the event identifier.
  /// [timestamp] is the occurrence timestamp in milliseconds for recurring events.
  ///
  /// On iOS, presents the event in a modal using EKEventViewController.
  /// On Android, opens the event using an Intent with ACTION_VIEW.
  Future<void> showEventModal(String eventId, int? timestamp);

  /// Creates a new event in the specified calendar.
  ///
  /// [calendarId] is the ID of the calendar to create the event in.
  /// [title] is the event title.
  /// [startDate] is the start date/time.
  /// [endDate] is the end date/time.
  /// [isAllDay] indicates if this is an all-day event.
  /// [description] is optional event notes/description.
  /// [location] is optional event location.
  /// [url] is optional URL associated with the event.
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
    String? url,
    String? timeZone,
    String availability,
  );

  /// Deletes an event from the device.
  ///
  /// [eventId] is the event identifier.
  ///
  /// **For recurring events**: This will delete the ENTIRE series (all past and
  /// future occurrences). Single-instance deletion is not supported to maintain
  /// consistent behavior across platforms.
  ///
  /// Requires calendar write permissions.
  Future<void> deleteEvent(String eventId);

  /// Updates an existing event on the device.
  ///
  /// [eventId] is the event identifier.
  ///
  /// **For recurring events**: This will update the ENTIRE series (all past and
  /// future occurrences). Single-instance updates are not supported to maintain
  /// consistent behavior across platforms.
  ///
  /// All field parameters are optional - only provided fields will be updated:
  /// - [title] - new event title
  /// - [startDate] - new start date/time
  /// - [endDate] - new end date/time
  /// - [description] - new event description
  /// - [location] - new event location
  /// - [isAllDay] - change between all-day and timed event
  /// - [timeZone] - new timezone identifier
  ///
  /// At least one field must be provided.
  /// Requires calendar write permissions.
  Future<void> updateEvent(
    String eventId, {
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
  });
}
