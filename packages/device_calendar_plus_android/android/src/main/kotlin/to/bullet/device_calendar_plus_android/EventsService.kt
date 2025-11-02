package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.provider.CalendarContract
import java.util.Date

class EventsService(private val activity: Activity) {
    
    fun retrieveEvents(
        startDate: Date,
        endDate: Date,
        calendarIds: List<String>?
    ): Result<List<Map<String, Any>>> {
        val events = mutableListOf<Map<String, Any>>()
        
        // Convert dates to milliseconds
        val startMillis = startDate.time
        val endMillis = endDate.time
        
        // Build URI with date range for Instances API
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(startMillis.toString())
            .appendPath(endMillis.toString())
            .build()
        
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.AVAILABILITY,
            CalendarContract.Instances.STATUS,
            CalendarContract.Instances.EVENT_TIMEZONE
        )
        
        // Build selection clause for calendar filtering
        var selection: String? = null
        var selectionArgs: Array<String>? = null
        
        if (calendarIds != null && calendarIds.isNotEmpty()) {
            val placeholders = calendarIds.joinToString(",") { "?" }
            selection = "${CalendarContract.Instances.CALENDAR_ID} IN ($placeholders)"
            selectionArgs = calendarIds.toTypedArray()
        }
        
        try {
            activity.contentResolver.query(
                uri,
                projection,
                selection,
                selectionArgs,
                "${CalendarContract.Instances.BEGIN} ASC"
            )?.use { cursor ->
                val eventIdIndex = cursor.getColumnIndex(CalendarContract.Instances.EVENT_ID)
                val calendarIdIndex = cursor.getColumnIndex(CalendarContract.Instances.CALENDAR_ID)
                val titleIndex = cursor.getColumnIndex(CalendarContract.Instances.TITLE)
                val descriptionIndex = cursor.getColumnIndex(CalendarContract.Instances.DESCRIPTION)
                val locationIndex = cursor.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
                val beginIndex = cursor.getColumnIndex(CalendarContract.Instances.BEGIN)
                val endIndex = cursor.getColumnIndex(CalendarContract.Instances.END)
                val allDayIndex = cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY)
                val availabilityIndex = cursor.getColumnIndex(CalendarContract.Instances.AVAILABILITY)
                val statusIndex = cursor.getColumnIndex(CalendarContract.Instances.STATUS)
                val timeZoneIndex = cursor.getColumnIndex(CalendarContract.Instances.EVENT_TIMEZONE)
                
                while (cursor.moveToNext()) {
                    val eventId = cursor.getString(eventIdIndex)
                    val calendarId = cursor.getString(calendarIdIndex)
                    val title = if (!cursor.isNull(titleIndex)) cursor.getString(titleIndex) else ""
                    val description = if (!cursor.isNull(descriptionIndex)) cursor.getString(descriptionIndex) else null
                    val location = if (!cursor.isNull(locationIndex)) cursor.getString(locationIndex) else null
                    var begin = cursor.getLong(beginIndex)
                    var end = cursor.getLong(endIndex)
                    val allDay = if (!cursor.isNull(allDayIndex)) cursor.getInt(allDayIndex) == 1 else false
                    val availability = if (!cursor.isNull(availabilityIndex)) cursor.getInt(availabilityIndex) else 0
                    val status = if (!cursor.isNull(statusIndex)) cursor.getInt(statusIndex) else 0
                    val timeZone = if (!cursor.isNull(timeZoneIndex)) cursor.getString(timeZoneIndex) else null
                    
                    // For all-day events, Android stores times in UTC but we want local floating dates
                    // Convert UTC milliseconds to local date at midnight
                    if (allDay) {
                        val calendar = java.util.Calendar.getInstance()
                        calendar.timeInMillis = begin
                        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
                        calendar.set(java.util.Calendar.MINUTE, 0)
                        calendar.set(java.util.Calendar.SECOND, 0)
                        calendar.set(java.util.Calendar.MILLISECOND, 0)
                        begin = calendar.timeInMillis
                        
                        calendar.timeInMillis = end
                        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
                        calendar.set(java.util.Calendar.MINUTE, 0)
                        calendar.set(java.util.Calendar.SECOND, 0)
                        calendar.set(java.util.Calendar.MILLISECOND, 0)
                        end = calendar.timeInMillis
                    }
                    
                    val eventMap = mutableMapOf<String, Any>(
                        "eventId" to eventId,
                        "calendarId" to calendarId,
                        "title" to title,
                        "startDate" to begin,
                        "endDate" to end,
                        "isAllDay" to allDay,
                        "availability" to availabilityToString(availability),
                        "status" to statusToString(status)
                    )
                    
                    description?.let { eventMap["description"] = it }
                    location?.let { eventMap["location"] = it }
                    
                    // Add timezone for timed events only (null for all-day events)
                    if (!allDay && timeZone != null) {
                        eventMap["timeZone"] = timeZone
                    }
                    
                    events.add(eventMap)
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
                    "Failed to query events: ${e.message}"
                )
            )
        }
        
        return Result.success(events)
    }
    
    private fun availabilityToString(availability: Int): String {
        return when (availability) {
            CalendarContract.Events.AVAILABILITY_BUSY -> "busy"
            CalendarContract.Events.AVAILABILITY_FREE -> "free"
            CalendarContract.Events.AVAILABILITY_TENTATIVE -> "tentative"
            else -> "busy"
        }
    }
    
    private fun statusToString(status: Int): String {
        return when (status) {
            CalendarContract.Events.STATUS_CONFIRMED -> "confirmed"
            CalendarContract.Events.STATUS_TENTATIVE -> "tentative"
            CalendarContract.Events.STATUS_CANCELED -> "canceled"
            else -> "none"
        }
    }
}

