/// Base class for platform-specific calendar creation options.
///
/// Platform implementations can extend this class to provide
/// platform-specific options when creating calendars.
///
/// Platform-specific implementations append the platform name:
/// - Android: [CreateCalendarOptionsAndroid]
/// - iOS: [CreateCalendarOptionsIos]
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
