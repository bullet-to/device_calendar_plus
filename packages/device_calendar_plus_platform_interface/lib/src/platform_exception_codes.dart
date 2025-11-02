/// Platform exception codes used for communication between native and Dart.
///
/// These constants ensure consistency between native platform code
/// (Kotlin/Swift) and Dart error handling.
class PlatformExceptionCodes {
  PlatformExceptionCodes._();

  /// Calendar permissions are not declared in the app's manifest.
  ///
  /// Android: Missing READ_CALENDAR or WRITE_CALENDAR in AndroidManifest.xml
  /// iOS: Missing NSCalendarsUsageDescription in Info.plist
  static const String permissionsNotDeclared = 'PERMISSIONS_NOT_DECLARED';
}
