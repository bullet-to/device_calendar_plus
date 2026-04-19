import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';

/// iOS-specific options for creating a calendar.
///
/// Use this class to specify which source (account) the calendar should be
/// created under. Pass the [CalendarSource.id] from [DeviceCalendar.listSources].
///
/// If [platformOptions] is omitted from [DeviceCalendar.createCalendar], the
/// default tiered fallback is used (default calendar's source → first CalDAV → local).
///
/// Example:
/// ```dart
/// final sources = await plugin.listSources();
/// final icloud = sources.firstWhere((s) => s.accountName == 'iCloud');
///
/// await plugin.createCalendar(
///   name: 'Work Calendar',
///   platformOptions: CreateCalendarOptionsIos(sourceId: icloud.id),
/// );
/// ```
class CreateCalendarOptionsIos extends CreateCalendarPlatformOptions {
  /// The source identifier to create the calendar under.
  ///
  /// This is the [CalendarSource.id] value, which corresponds to
  /// `EKSource.sourceIdentifier` on iOS.
  final String sourceId;

  /// Creates iOS-specific calendar creation options.
  ///
  /// [sourceId] is the source identifier from [CalendarSource.id].
  const CreateCalendarOptionsIos({
    required this.sourceId,
  });
}
