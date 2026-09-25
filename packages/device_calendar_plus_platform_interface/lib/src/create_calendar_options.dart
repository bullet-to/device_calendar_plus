/// Base class for platform-specific calendar creation options.
///
/// Platform implementations can extend this class to provide
/// platform-specific options when creating calendars.
///
/// Platform-specific implementations append the platform name:
/// - Android: `CreateCalendarOptionsAndroid` (account name and type)
/// - iOS: `CreateCalendarOptionsIos` (source identifier)
///
/// Example:
/// ```dart
/// await plugin.createCalendar(
///   name: 'My Calendar',
///   platformOptions: CreateCalendarOptionsAndroid(accountName: 'MyApp'),
/// );
/// ```
abstract class CreateCalendarPlatformOptions {
  const CreateCalendarPlatformOptions();
}
