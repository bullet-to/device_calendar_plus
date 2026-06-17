/// Represents the current status of calendar permissions.
enum CalendarPermissionStatus {
  /// Full read and write access to calendars.
  granted,

  /// Permission has been permanently denied — the system dialog can no longer
  /// be shown (on Android, the user chose "Don't ask again"). Use
  /// [DeviceCalendar.openAppSettings] to send the user to settings.
  denied,

  /// Write-only access — add events without reading existing data. Request it
  /// with `requestPermissions(level: CalendarAccessLevel.writeOnly)`.
  ///
  /// iOS 16 and below has no write-only tier, so a write-only request there
  /// resolves to [granted] instead.
  writeOnly,

  /// Access is restricted by device policies (iOS only).
  ///
  /// This typically occurs when parental controls, Mobile Device Management (MDM),
  /// or Screen Time restrictions prevent calendar access. The user cannot grant
  /// permission even if they want to.
  ///
  /// This status is never returned on Android.
  restricted,

  /// Permission has not been granted yet, but can still be requested — calling
  /// [DeviceCalendar.requestPermissions] in this state shows the system dialog.
  ///
  /// On Android this covers both "never asked" and "denied once but can still
  /// ask again"; a permanent denial returns [denied] instead.
  notDetermined,
}
