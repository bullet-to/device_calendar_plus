/// How [DeviceCalendar] obtains calendar permission when a method is called
/// before access has been granted.
///
/// Opt in by setting [DeviceCalendar.autoPermissions]. While it is `null` (the
/// default) methods never prompt on their own — you call
/// [DeviceCalendar.requestPermissions] yourself, exactly as before.
///
/// When a mode is set, each method ensures permission on first use: if the
/// status is [CalendarPermissionStatus.notDetermined] it requests the
/// appropriate tier, and if access is ultimately not granted it throws a
/// [DeviceCalendarException] with [DeviceCalendarError.permissionDenied].
///
/// Auto-permissions only act on a fresh ([CalendarPermissionStatus.notDetermined])
/// status — they never silently escalate a tier you already hold. An app that
/// holds write-only and then calls a read operation gets a `permissionDenied`,
/// not a surprise upgrade prompt; call [DeviceCalendar.requestPermissions] with
/// [CalendarAccessLevel.full] yourself when you want to ask for the upgrade
/// (and to control where any priming UI appears).
enum AutoPermissionMode {
  /// Request the minimum tier each operation needs: add-only operations (such
  /// as [DeviceCalendar.createEvent]) ask for write-only access; every other
  /// operation asks for full access.
  ///
  /// Defers the heavier full-access prompt until an operation actually needs to
  /// read. Best for apps that mostly add events and only occasionally read.
  asNeeded,

  /// Request full read/write access on the first operation that needs
  /// permission, whatever that operation is.
  ///
  /// The simplest choice for any app that reads calendar data regularly.
  full,
}
