package to.bullet.device_calendar_plus_android

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat

class CalendarService(private val activity: Activity) {
    
    fun listCalendars(): Result<List<Map<String, Any>>> {
        val calendars = mutableListOf<Map<String, Any>>()
        
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE
        )
        
        try {
            activity.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection,
                null,
                null,
                null
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(CalendarContract.Calendars._ID)
                val nameIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
                val colorIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_COLOR)
                val accessLevelIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
                val accountNameIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_NAME)
                val accountTypeIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_TYPE)
                val isPrimaryIndex = cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
                val visibleIndex = cursor.getColumnIndex(CalendarContract.Calendars.VISIBLE)
                
                while (cursor.moveToNext()) {
                    val id = cursor.getString(idIndex)
                    val name = cursor.getString(nameIndex)
                    val color = if (!cursor.isNull(colorIndex)) cursor.getInt(colorIndex) else null
                    val accessLevel = cursor.getInt(accessLevelIndex)
                    val accountName = if (!cursor.isNull(accountNameIndex)) cursor.getString(accountNameIndex) else null
                    val accountType = if (!cursor.isNull(accountTypeIndex)) cursor.getString(accountTypeIndex) else null
                    val isPrimary = if (!cursor.isNull(isPrimaryIndex)) cursor.getInt(isPrimaryIndex) == 1 else false
                    val visible = if (!cursor.isNull(visibleIndex)) cursor.getInt(visibleIndex) == 1 else true
                    
                    // Determine if read-only based on access level
                    val readOnly = accessLevel < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
                    
                    // Convert color to hex string
                    val colorHex = color?.let { ColorHelper.colorToHex(it) }
                    
                    val calendarMap = mutableMapOf<String, Any>(
                        "id" to id,
                        "name" to name,
                        "readOnly" to readOnly,
                        "isPrimary" to isPrimary,
                        "hidden" to !visible // Invert visible to hidden
                    )
                    
                    colorHex?.let { calendarMap["colorHex"] = it }
                    accountName?.let { calendarMap["accountName"] = it }
                    accountType?.let { calendarMap["accountType"] = it }
                    
                    calendars.add(calendarMap)
                }
            }
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to query calendars: ${e.message}"
                )
            )
        }
        
        return Result.success(calendars)
    }
    
    fun createCalendar(name: String, colorHex: String?): Result<String> {
        // Check for write calendar permission
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CALENDAR) 
            != PackageManager.PERMISSION_GRANTED) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        val accountName = "local"
        val accountType = CalendarContract.ACCOUNT_TYPE_LOCAL
        
        // Android automatically creates the account when inserting the first calendar
        try {
            val values = android.content.ContentValues().apply {
                put(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
                put(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
                put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
                put(CalendarContract.Calendars.NAME, name)
                put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
                put(CalendarContract.Calendars.OWNER_ACCOUNT, accountName)
                put(CalendarContract.Calendars.VISIBLE, 1)
                put(CalendarContract.Calendars.SYNC_EVENTS, 1)
                
                // Set color if provided
                if (colorHex != null) {
                    val color = ColorHelper.hexToColor(colorHex)
                    put(CalendarContract.Calendars.CALENDAR_COLOR, color)
                }
            }
            
            val uri = activity.contentResolver.insert(
                CalendarContract.Calendars.CONTENT_URI
                    .buildUpon()
                    .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
                    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
                    .build(),
                values
            )
            
            if (uri != null) {
                val calendarId = uri.lastPathSegment
                if (calendarId != null) {
                    return Result.success(calendarId)
                }
            }
            
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to create calendar: No calendar ID returned"
                )
            )
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to create calendar: ${e.message}"
                )
            )
        }
    }
    
    fun updateCalendar(calendarId: String, name: String?, colorHex: String?): Result<Unit> {
        // Check for write calendar permission
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CALENDAR) 
            != PackageManager.PERMISSION_GRANTED) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            // Prepare values to update
            val values = android.content.ContentValues()
            
            // Update name if provided
            if (name != null) {
                values.put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
                values.put(CalendarContract.Calendars.NAME, name)
            }
            
            // Update color if provided
            if (colorHex != null) {
                val color = ColorHelper.hexToColor(colorHex)
                values.put(CalendarContract.Calendars.CALENDAR_COLOR, color)
            }
            
            // Update the calendar
            val updatedRows = activity.contentResolver.update(
                CalendarContract.Calendars.CONTENT_URI,
                values,
                "${CalendarContract.Calendars._ID} = ?",
                arrayOf(calendarId)
            )
            
            if (updatedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "Calendar with ID $calendarId not found"
                    )
                )
            }
            
            return Result.success(Unit)
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to update calendar: ${e.message}"
                )
            )
        }
    }
    
    fun deleteCalendar(calendarId: String): Result<Unit> {
        // Check for write calendar permission
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CALENDAR) 
            != PackageManager.PERMISSION_GRANTED) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            val deletedRows = activity.contentResolver.delete(
                CalendarContract.Calendars.CONTENT_URI,
                "${CalendarContract.Calendars._ID} = ?",
                arrayOf(calendarId)
            )
            
            if (deletedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "Calendar with ID $calendarId not found"
                    )
                )
            }
            
            return Result.success(Unit)
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to delete calendar: ${e.message}"
                )
            )
        }
    }
    
}

data class CalendarException(
    val code: String,
    override val message: String
) : Exception(message)

