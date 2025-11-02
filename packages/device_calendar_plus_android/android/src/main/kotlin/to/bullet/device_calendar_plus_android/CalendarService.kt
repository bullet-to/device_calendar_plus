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
                    val colorHex = color?.let { colorToHex(it) }
                    
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
    
    private fun colorToHex(color: Int): String {
        // Android color is ARGB, we want RGB hex string
        return String.format("#%06X", 0xFFFFFF and color)
    }
}

data class CalendarException(
    val code: String,
    override val message: String
) : Exception(message)

