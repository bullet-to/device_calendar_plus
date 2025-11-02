/// Represents the current status of calendar permissions.
enum CalendarPermissionStatus {
  /// Full read and write access to calendars.
  granted,

  /// Permission has been denied by the user.
  denied,

  /// Write-only access to calendars (iOS 17+ only).
  ///
  /// On iOS 17 and later, apps can request write-only access to add events
  /// without being able to read existing calendar data.
  ///
  /// This status is never returned on Android.
  writeOnly,

  /// Access is restricted by device policies (iOS only).
  ///
  /// This typically occurs when parental controls, Mobile Device Management (MDM),
  /// or Screen Time restrictions prevent calendar access. The user cannot grant
  /// permission even if they want to.
  ///
  /// This status is never returned on Android.
  restricted,

  /// Permission has not been requested yet (iOS only).
  ///
  /// This is the initial state before the app has requested calendar permissions.
  ///
  /// This status is never returned on Android.
  notDetermined,
}
