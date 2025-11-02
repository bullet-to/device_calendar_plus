package to.bullet.device_calendar_plus_android

/**
 * Platform exception codes matching PlatformExceptionCodes in Dart.
 * 
 * These codes are sent via method channel errors and caught/transformed
 * by the Dart layer into DeviceCalendarException.
 */
object PlatformExceptionCodes {
    /**
     * Calendar permissions not declared in AndroidManifest.xml.
     * 
     * Corresponds to DeviceCalendarError.permissionsNotDeclared in Dart.
     */
    const val PERMISSIONS_NOT_DECLARED = "PERMISSIONS_NOT_DECLARED"
}

