/// The tier of calendar access to request from the user.
///
/// Passed to [DeviceCalendar.requestPermissions] to choose how much access the
/// system prompt asks for. An add-only app can request [writeOnly] for the
/// gentler "Add Events Only" prompt instead of full read/write.
enum CalendarAccessLevel {
  /// Full read and write access. A granted request reports
  /// [CalendarPermissionStatus.granted].
  full,

  /// Write-only access — the app can add events but not read existing ones, for
  /// the gentler "Add Events Only" prompt. A granted request reports
  /// [CalendarPermissionStatus.writeOnly].
  ///
  /// Not a permanent ceiling: a later [full] request upgrades the app in-app.
  /// iOS 16 and below has no write-only tier, so the request falls back to full
  /// access and reports [CalendarPermissionStatus.granted].
  writeOnly,
}
