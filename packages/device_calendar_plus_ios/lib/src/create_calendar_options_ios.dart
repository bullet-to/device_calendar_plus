import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';

/// iOS-specific options for creating a calendar.
///
/// Use this class to specify which calendar source to create the calendar in.
/// By default, calendars are created in the local source. To create a calendar
/// that syncs with iCloud, specify a source with `sourceTitle: 'iCloud'` or
/// use the source ID from [DeviceCalendar.listSources].
///
/// Use [DeviceCalendar.listSources] to discover available sources.
///
/// Example:
/// ```dart
/// // Create a local calendar (default behavior)
/// await plugin.createCalendar(name: 'My Calendar');
///
/// // Create a calendar that syncs with iCloud
/// await plugin.createCalendar(
///   name: 'My iCloud Calendar',
///   platformOptions: CreateCalendarOptionsIos(sourceTitle: 'iCloud'),
/// );
///
/// // Create a calendar using a specific source ID
/// final sources = await plugin.listSources();
/// final icloudSource = sources.firstWhere((s) => s.title == 'iCloud');
/// await plugin.createCalendar(
///   name: 'My Calendar',
///   platformOptions: CreateCalendarOptionsIos(sourceId: icloudSource.id),
/// );
/// ```
///
/// **Known Limitation**: Google accounts on iOS may not allow programmatic
/// calendar creation. The error "That account does not allow calendars to be
/// added or removed" has been reported. For iOS, using iCloud is recommended.
class CreateCalendarOptionsIos extends CreateCalendarPlatformOptions {
  /// The source identifier to create the calendar in.
  ///
  /// This takes precedence over [sourceTitle] if both are provided.
  /// Get valid source IDs from [DeviceCalendar.listSources].
  final String? sourceId;

  /// The source title to search for (e.g., "iCloud").
  ///
  /// If [sourceId] is not provided, the plugin will search for a source
  /// with this title. This is a convenience method for common sources.
  ///
  /// Common values:
  /// - `"iCloud"` - Apple's iCloud calendar sync
  /// - `"On My iPhone"` or `"On My iPad"` - Local device storage
  final String? sourceTitle;

  /// Creates iOS-specific calendar creation options.
  ///
  /// At least one of [sourceId] or [sourceTitle] should be provided.
  /// If neither is provided, the default behavior is to try iCloud first,
  /// then fall back to local storage.
  const CreateCalendarOptionsIos({this.sourceId, this.sourceTitle});
}
