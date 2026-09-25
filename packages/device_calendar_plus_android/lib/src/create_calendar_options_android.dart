import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';

/// Android-specific options for creating a calendar.
///
/// Use this class to specify the account the calendar is created under. Only
/// the local account type (`ACCOUNT_TYPE_LOCAL`, the default) accepts new
/// calendars from a third-party app; any other [accountType] is refused with
/// `DeviceCalendarError.readOnly`, matching what
/// [CalendarSource.supportsCalendarCreation] reports for it. Other account
/// types belong to their sync adapters, which can wipe a calendar they didn't
/// create.
///
/// Example:
/// ```dart
/// await plugin.createCalendar(
///   name: 'My Calendar',
///   platformOptions: CreateCalendarOptionsAndroid(accountName: 'MyApp'),
/// );
/// ```
class CreateCalendarOptionsAndroid extends CreateCalendarPlatformOptions {
  /// The account name for the calendar.
  ///
  /// Calendars with the same account name will be grouped together
  /// in the device's calendar app.
  /// Defaults to "local" if not specified via platform options.
  final String accountName;

  /// The account type for the calendar.
  ///
  /// Use values from [CalendarSource.accountType] returned by
  /// [DeviceCalendar.listSources]. Only `ACCOUNT_TYPE_LOCAL` (`"LOCAL"`) is
  /// accepted; a sync-adapter type such as `"com.google"` throws
  /// `DeviceCalendarError.readOnly`.
  ///
  /// If not provided, defaults to `ACCOUNT_TYPE_LOCAL`.
  final String? accountType;

  /// Creates Android-specific calendar creation options.
  ///
  /// [accountName] is the account name for the calendar.
  /// [accountType] is optional — defaults to LOCAL if omitted.
  const CreateCalendarOptionsAndroid({
    required this.accountName,
    this.accountType,
  });
}
