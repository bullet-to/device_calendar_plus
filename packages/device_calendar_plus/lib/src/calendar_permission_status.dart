/// Represents the current status of calendar permissions.
enum CalendarPermissionStatus {
  /// Full read and write access to calendars.
  granted,

  /// Permission has been permanently denied by the user.
  ///
  /// On Android, this means the user selected "Don't ask again" and the
  /// permission dialog can no longer be shown. Use [DeviceCalendar.openAppSettings]
  /// to direct the user to the system settings page.
  ///
  /// On iOS, this maps to `EKAuthorizationStatus.denied`.
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

  /// Permission has not been granted yet, but can still be requested.
  ///
  /// Calling [DeviceCalendar.requestPermissions] while in this state will show
  /// the system permission dialog.
  ///
  /// On iOS, this maps directly to the `EKAuthorizationStatus.notDetermined` state.
  ///
  /// On Android, this covers both "never asked" and "denied once but can still
  /// ask again". Android's `checkSelfPermission()` returns `PERMISSION_DENIED`
  /// in both cases, so a `SharedPreferences` flag combined with
  /// `shouldShowRequestPermissionRationale()` is used to detect when the
  /// permission has been permanently denied (which returns [denied] instead).
  notDetermined,
}
