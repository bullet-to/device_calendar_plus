package to.bullet.device_calendar_plus_android

/**
 * Platform exception codes matching PlatformExceptionCodes in Dart.
 * 
 * These codes are sent via method channel errors and caught/transformed
 * by the Dart layer into DeviceCalendarException.
 */
object PlatformExceptionCodes {
    // Permission-related errors
    
    /**
     * Calendar permissions not declared in AndroidManifest.xml.
     * 
     * Missing READ_CALENDAR or WRITE_CALENDAR in AndroidManifest.xml
     */
    const val PERMISSIONS_NOT_DECLARED = "PERMISSIONS_NOT_DECLARED"
    
    /**
     * Calendar permission denied by user.
     * 
     * User has explicitly denied calendar access, or security exception occurred.
     */
    const val PERMISSION_DENIED = "PERMISSION_DENIED"
    
    // Input validation errors
    
    /**
     * Invalid arguments passed to a method.
     * 
     * Parameters are missing, of wrong type, or contain invalid values.
     */
    const val INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    
    // Resource errors
    
    /**
     * Requested calendar or event not found.
     * 
     * The calendar ID or event instance ID doesn't exist.
     */
    const val NOT_FOUND = "NOT_FOUND"
    
    /**
     * Calendar is read-only and cannot be modified.
     * 
     * Attempting to update or delete a calendar that doesn't allow modifications.
     */
    const val READ_ONLY = "READ_ONLY"
    
    // Operation errors
    
    /**
     * Operation is not supported on this platform or in this context.
     * 
     * Examples:
     * - Single recurring instance updates/deletes (Android limitation)
     * - Platform-specific feature not available
     */
    const val NOT_SUPPORTED = "NOT_SUPPORTED"
    
    /**
     * Calendar operation failed.
     * 
     * Save, update, or delete operation failed for reasons other than permissions.
     * Check error message for details.
     */
    const val OPERATION_FAILED = "OPERATION_FAILED"
    
    // System/availability errors
    
    /**
     * Calendar system is not available.
     * 
     * Examples:
     * - Calendar app not installed
     * - Event store unavailable
     */
    const val CALENDAR_UNAVAILABLE = "CALENDAR_UNAVAILABLE"
    
    // Generic errors
    
    /**
     * An unknown or unexpected error occurred.
     * 
     * Used for unexpected exceptions that don't fit other categories.
     * Check error message for details.
     */
    const val UNKNOWN_ERROR = "UNKNOWN_ERROR"
}

