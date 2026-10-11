/// Represents the current status of calendar permissions.
enum CalendarPermissionStatus {
  /// Full read and write access to calendars.
  granted,

  /// Permission was denied. Use [DeviceCalendar.openAppSettings] to send the
  /// user to settings.
  ///
  /// From [DeviceCalendar.hasPermissions] this means a *permanent* denial —
  /// the system dialog can no longer be shown (on Android, the user chose
  /// "Don't ask again"). [DeviceCalendar.requestPermissions] additionally
  /// reports a just-declined prompt as [denied] on both platforms; on Android
  /// that first decline is still re-askable, so a later
  /// [DeviceCalendar.hasPermissions] there, called from an Activity, reports
  /// [notDetermined] rather than [denied].
  ///
  /// On Android without an Activity (a background context), the OS can't say
  /// whether a denial is still re-askable, so any denial recorded by this
  /// plugin is treated as permanent and reports [denied] — matching iOS,
  /// where a decline is terminal.
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
  /// On Android without an Activity (a background context),
  /// [DeviceCalendar.requestPermissions] can't show the dialog and fails with
  /// [DeviceCalendarError.operationFailed].
  ///
  /// On Android, called from an Activity, this covers both "never asked" and
  /// "denied once but can still ask again"; a permanent denial returns
  /// [denied] instead. Android tells the two apart using denials made through
  /// this plugin, so a permanent denial made via another library (e.g.
  /// permission_handler) reads as [notDetermined] until one
  /// [DeviceCalendar.requestPermissions] call (which returns [denied] without
  /// showing a dialog) records it.
  notDetermined,
}
