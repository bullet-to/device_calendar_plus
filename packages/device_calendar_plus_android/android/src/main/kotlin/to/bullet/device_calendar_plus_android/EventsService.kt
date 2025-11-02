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
            CalendarContract.Instances.EVENT_TIMEZONE,
            CalendarContract.Instances.RRULE
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
                while (cursor.moveToNext()) {
                    val eventMap = buildEventMapFromCursor(
                        cursor,
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
                        CalendarContract.Instances.EVENT_TIMEZONE,
                        CalendarContract.Instances.RRULE
                    )
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
    
    private fun buildEventMapFromCursor(
        cursor: android.database.Cursor,
        eventIdColumn: String,
        calendarIdColumn: String,
        titleColumn: String,
        descriptionColumn: String,
        locationColumn: String,
        startColumn: String,
        endColumn: String,
        allDayColumn: String,
        availabilityColumn: String,
        statusColumn: String,
        timeZoneColumn: String,
        recurrenceRuleColumn: String
    ): Map<String, Any> {
        val eventIdIndex = cursor.getColumnIndex(eventIdColumn)
        val calendarIdIndex = cursor.getColumnIndex(calendarIdColumn)
        val titleIndex = cursor.getColumnIndex(titleColumn)
        val descriptionIndex = cursor.getColumnIndex(descriptionColumn)
        val locationIndex = cursor.getColumnIndex(locationColumn)
        val startIndex = cursor.getColumnIndex(startColumn)
        val endIndex = cursor.getColumnIndex(endColumn)
        val allDayIndex = cursor.getColumnIndex(allDayColumn)
        val availabilityIndex = cursor.getColumnIndex(availabilityColumn)
        val statusIndex = cursor.getColumnIndex(statusColumn)
        val timeZoneIndex = cursor.getColumnIndex(timeZoneColumn)
        val recurrenceRuleIndex = cursor.getColumnIndex(recurrenceRuleColumn)
        
        val eventId = cursor.getString(eventIdIndex)
        val calendarId = cursor.getString(calendarIdIndex)
        val title = if (!cursor.isNull(titleIndex)) cursor.getString(titleIndex) else ""
        val description = if (!cursor.isNull(descriptionIndex)) cursor.getString(descriptionIndex) else null
        val location = if (!cursor.isNull(locationIndex)) cursor.getString(locationIndex) else null
        var start = cursor.getLong(startIndex)
        var end = if (!cursor.isNull(endIndex)) cursor.getLong(endIndex) else start
        val allDay = if (!cursor.isNull(allDayIndex)) cursor.getInt(allDayIndex) == 1 else false
        val availability = if (!cursor.isNull(availabilityIndex)) cursor.getInt(availabilityIndex) else 0
        val status = if (!cursor.isNull(statusIndex)) cursor.getInt(statusIndex) else 0
        val timeZone = if (!cursor.isNull(timeZoneIndex)) cursor.getString(timeZoneIndex) else null
        val recurrenceRule = if (!cursor.isNull(recurrenceRuleIndex)) cursor.getString(recurrenceRuleIndex) else null
        
        // For all-day events, Android stores times in UTC but we want local floating dates
        if (allDay) {
            val calendar = java.util.Calendar.getInstance()
            calendar.timeInMillis = start
            calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
            calendar.set(java.util.Calendar.MINUTE, 0)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)
            start = calendar.timeInMillis
            
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
            "startDate" to start,
            "endDate" to end,
            "isAllDay" to allDay,
            "availability" to availabilityToString(availability),
            "status" to statusToString(status)
        )
        
        description?.let { eventMap["description"] = it }
        location?.let { eventMap["location"] = it }
        
        // Add timezone for timed events only
        if (!allDay && timeZone != null) {
            eventMap["timeZone"] = timeZone
        }
        
        // Set isRecurring flag
        eventMap["isRecurring"] = (recurrenceRule != null)
        
        return eventMap
    }
    
    fun getEvent(
        eventId: String,
        occurrenceDate: Date?
    ): Result<Map<String, Any>?> {
        if (occurrenceDate != null) {
            // Query ±24 hours around the occurrence date
            val occurrenceMillis = occurrenceDate.time
            val startMillis = occurrenceMillis - (24 * 60 * 60 * 1000)
            val endMillis = occurrenceMillis + (24 * 60 * 60 * 1000)
            
            val startDate = Date(startMillis)
            val endDate = Date(endMillis)
            
            // Use existing retrieveEvents to get events in range
            val eventsResult = retrieveEvents(startDate, endDate, null)
            
            return eventsResult.mapCatching { events ->
                // Filter by eventId and return first match
                events.firstOrNull { it["eventId"] == eventId }
            }
        } else {
            // Get master event directly from Events table
            val projection = arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.CALENDAR_ID,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DESCRIPTION,
                CalendarContract.Events.EVENT_LOCATION,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.ALL_DAY,
                CalendarContract.Events.AVAILABILITY,
                CalendarContract.Events.STATUS,
                CalendarContract.Events.EVENT_TIMEZONE,
                CalendarContract.Events.RRULE
            )
            
            val selection = "${CalendarContract.Events._ID} = ?"
            val selectionArgs = arrayOf(eventId)
            
            try {
                activity.contentResolver.query(
                    CalendarContract.Events.CONTENT_URI,
                    projection,
                    selection,
                    selectionArgs,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val eventMap = buildEventMapFromCursor(
                            cursor,
                            CalendarContract.Events._ID,
                            CalendarContract.Events.CALENDAR_ID,
                            CalendarContract.Events.TITLE,
                            CalendarContract.Events.DESCRIPTION,
                            CalendarContract.Events.EVENT_LOCATION,
                            CalendarContract.Events.DTSTART,
                            CalendarContract.Events.DTEND,
                            CalendarContract.Events.ALL_DAY,
                            CalendarContract.Events.AVAILABILITY,
                            CalendarContract.Events.STATUS,
                            CalendarContract.Events.EVENT_TIMEZONE,
                            CalendarContract.Events.RRULE
                        )
                        return Result.success(eventMap)
                    } else {
                        return Result.success(null)
                    }
                }
                
                return Result.success(null)
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
                        "Failed to query event: ${e.message}"
                    )
                )
            }
        }
    }
}

