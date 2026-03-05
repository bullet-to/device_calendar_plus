import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';

/// Android-specific options for creating a calendar.
///
/// Use this class to specify the account name and type for the calendar on
/// Android. By default, calendars are created as local calendars that don't
/// sync. To create a calendar that syncs with a cloud account (e.g., Google
/// Calendar), specify both [accountName] and [accountType].
///
/// Use [DeviceCalendar.listSources] to discover available accounts and their
/// types.
///
/// Example:
/// ```dart
/// // Create a local calendar (no cloud sync)
/// await plugin.createCalendar(
///   name: 'My Calendar',
///   platformOptions: CreateCalendarOptionsAndroid(accountName: 'MyApp'),
/// );
///
/// // Create a calendar that syncs with Google Calendar
/// await plugin.createCalendar(
///   name: 'My Synced Calendar',
///   platformOptions: CreateCalendarOptionsAndroid(
///     accountName: 'user@gmail.com',
///     accountType: 'com.google',
///   ),
/// );
/// ```
class CreateCalendarOptionsAndroid extends CreateCalendarPlatformOptions {
  /// The account name for the calendar.
  ///
  /// Calendars with the same account name will be grouped together
  /// in the device's calendar app.
  /// Defaults to "local" if not specified via platform options.
  ///
  /// For cloud sync, this should match an existing account on the device
  /// (e.g., "user@gmail.com" for Google accounts).
  final String accountName;

  /// The account type for the calendar.
  ///
  /// Common values:
  /// - `null` (default): Local calendar, no sync (uses `ACCOUNT_TYPE_LOCAL`)
  /// - `"com.google"`: Google Calendar sync
  /// - `"com.microsoft.exchange"`: Exchange/Outlook sync
  ///
  /// When null, defaults to local account type (no cloud sync).
  /// For cloud sync, use [DeviceCalendar.listSources] to find valid account
  /// types.
  final String? accountType;

  /// Creates Android-specific calendar creation options.
  ///
  /// [accountName] is the account name for the calendar.
  /// [accountType] is the account type. When null, creates a local calendar.
  const CreateCalendarOptionsAndroid({
    required this.accountName,
    this.accountType,
  });
}
