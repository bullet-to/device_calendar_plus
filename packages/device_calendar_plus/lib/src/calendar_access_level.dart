/// The tier of calendar access to request from the user.
///
/// Passed to [DeviceCalendar.requestPermissions] to choose how much access the
/// system prompt asks for. An add-only app can request [writeOnly] for the
/// gentler "Add Events Only" prompt instead of full read/write.
enum CalendarAccessLevel {
  /// Full read and write access.
  ///
  /// The user is asked to allow the app to view and manage calendar events.
  /// A granted request maps to [CalendarPermissionStatus.granted].
  ///
  /// - iOS 17+: `requestFullAccessToEvents`.
  /// - iOS 16 and below: `requestAccess(to: .event)` (the only tier available).
  /// - Android: requests both `READ_CALENDAR` and `WRITE_CALENDAR`.
  full,

  /// Write-only access — the app can add events but cannot read existing ones.
  ///
  /// This is the gentler prompt for add-only apps. A granted request maps to
  /// [CalendarPermissionStatus.writeOnly].
  ///
  /// - iOS 17+: `requestWriteOnlyAccessToEvents`. A distinct, durable tier — the
  ///   app cannot escalate to full access without the user changing it in
  ///   Settings.
  /// - iOS 16 and below: write-only does not exist, so this falls back to a
  ///   full-access request (`requestAccess(to: .event)`) and a granted result
  ///   reports [CalendarPermissionStatus.granted].
  /// - Android: requests only `WRITE_CALENDAR`. Note this is a softer boundary
  ///   than on iOS — `WRITE_CALENDAR` and `READ_CALENDAR` share the one
  ///   `CALENDAR` permission group, so after a write-only grant a later
  ///   full request escalates to read access **immediately, with no dialog**.
  writeOnly,
}
