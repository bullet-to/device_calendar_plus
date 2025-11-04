package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.provider.CalendarContract
import java.util.Date

class EventsService(private val activity: Activity) {
    
    fun retrieveEvents(
        startDate: Date,
        endDate: Date,
        calendarIds: List<String>?,
        eventId: String? = null
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
        
        // Build selection clause for calendar and event filtering
        val selections = mutableListOf<String>()
        val args = mutableListOf<String>()
        
        if (calendarIds != null && calendarIds.isNotEmpty()) {
            val placeholders = calendarIds.joinToString(",") { "?" }
            selections.add("${CalendarContract.Instances.CALENDAR_ID} IN ($placeholders)")
            args.addAll(calendarIds)
        }
        
        if (eventId != null) {
            selections.add("${CalendarContract.Instances.EVENT_ID} = ?")
            args.add(eventId)
        }
        
        val selection = if (selections.isNotEmpty()) selections.joinToString(" AND ") else null
        val selectionArgs = if (args.isNotEmpty()) args.toTypedArray() else null
        
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
        val rawStart = cursor.getLong(startIndex)
        val rawEnd = if (!cursor.isNull(endIndex)) cursor.getLong(endIndex) else rawStart
        val allDay = if (!cursor.isNull(allDayIndex)) cursor.getInt(allDayIndex) == 1 else false
        val availability = if (!cursor.isNull(availabilityIndex)) cursor.getInt(availabilityIndex) else 0
        val status = if (!cursor.isNull(statusIndex)) cursor.getInt(statusIndex) else 0
        val timeZone = if (!cursor.isNull(timeZoneIndex)) cursor.getString(timeZoneIndex) else null
        val recurrenceRule = if (!cursor.isNull(recurrenceRuleIndex)) cursor.getString(recurrenceRuleIndex) else null
        
        // Generate instanceId using RAW timestamps before any modifications
        val instanceId: String = if (recurrenceRule != null) {
            "$eventId@$rawStart"
        } else {
            eventId
        }
        
        // For all-day events, Android stores and returns UTC timestamps
        // We need to convert them to local time while preserving the calendar date
        val start: Long
        val end: Long
        
        if (allDay) {
            // Extract date components from UTC timestamp
            val utcCal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
            utcCal.timeInMillis = rawStart
            val startYear = utcCal.get(java.util.Calendar.YEAR)
            val startMonth = utcCal.get(java.util.Calendar.MONTH)
            val startDay = utcCal.get(java.util.Calendar.DAY_OF_MONTH)
            
            utcCal.timeInMillis = rawEnd
            val endYear = utcCal.get(java.util.Calendar.YEAR)
            val endMonth = utcCal.get(java.util.Calendar.MONTH)
            val endDay = utcCal.get(java.util.Calendar.DAY_OF_MONTH)
            
            // Create local timestamps with those date components
            val localCal = java.util.Calendar.getInstance()
            localCal.set(startYear, startMonth, startDay, 0, 0, 0)
            localCal.set(java.util.Calendar.MILLISECOND, 0)
            start = localCal.timeInMillis
            
            localCal.set(endYear, endMonth, endDay, 0, 0, 0)
            localCal.set(java.util.Calendar.MILLISECOND, 0)
            end = localCal.timeInMillis
        } else {
            start = rawStart
            end = rawEnd
        }
        
        val eventMap = mutableMapOf<String, Any>(
            "eventId" to eventId,
            "instanceId" to instanceId,
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
    
    fun getEvent(instanceId: String): Result<Map<String, Any>?> {
        // Parse instanceId: "eventId" or "eventId@timestamp"
        val parts = instanceId.split("@", limit = 2)
        val eventId = parts[0]
        
        if (parts.size == 2) {
            // Recurring event with timestamp
            val occurrenceMillis = parts[1].toLongOrNull() ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "Invalid instanceId format: $instanceId"
                )
            )
            
            // Query ±1 second around the exact occurrence time
            // We use a small window since we have the precise timestamp
            val startMillis = occurrenceMillis - 1000
            val endMillis = occurrenceMillis + 1000
            
            val startDate = Date(startMillis)
            val endDate = Date(endMillis)
            
            // Use retrieveEvents with event ID filter
            val eventsResult = retrieveEvents(startDate, endDate, null, eventId)
            
            return eventsResult.mapCatching { events ->
                // Find closest match to the occurrence time
                events.minByOrNull { event ->
                    val eventStart = event["startDate"] as? Long ?: return@minByOrNull Long.MAX_VALUE
                    kotlin.math.abs(eventStart - occurrenceMillis)
                }
            }
        } else {
            // Non-recurring event or master event
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

    /**
     * Shows a calendar event in a modal dialog.
     */
    fun showEvent(instanceId: String): Result<Unit> {
        return try {
            // Validate permissions
            if (android.content.pm.PackageManager.PERMISSION_GRANTED != 
                activity.checkSelfPermission(android.Manifest.permission.READ_CALENDAR)) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.PERMISSION_DENIED,
                        "Calendar permission denied. Call requestPermissions() first."
                    )
                )
            }

            // Parse instanceId: "eventId" or "eventId@timestamp"
            val parts = instanceId.split("@", limit = 2)
            val eventId = parts[0]
            
            val intent = Intent(Intent.ACTION_VIEW)
            
            // Build event URI
            val eventUri = android.content.ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI,
                eventId.toLong()
            )
            intent.data = eventUri
            
            // Add begin time for specific recurring event instances
            if (parts.size == 2) {
                val occurrenceMillis = parts[1].toLongOrNull()
                if (occurrenceMillis != null) {
                    intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, occurrenceMillis)
                }
            }
            
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            
            activity.startActivity(intent)
            Result.success(Unit)
        } catch (e: android.content.ActivityNotFoundException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Calendar app not found"
                )
            )
        } catch (e: SecurityException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to open event: ${e.message}"
                )
            )
        }
    }
    
    fun createEvent(
        calendarId: String,
        title: String,
        startDate: java.util.Date,
        endDate: java.util.Date,
        isAllDay: Boolean,
        description: String?,
        location: String?,
        timeZone: String?,
        availability: String
    ): Result<String> {
        // Check for write calendar permission
        if (android.content.pm.PackageManager.PERMISSION_GRANTED != 
            activity.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            // For all-day events, Android interprets timestamps as UTC to determine the calendar date
            // We need to convert local date components to UTC midnight to preserve the calendar date
            val startMillis: Long
            val endMillis: Long
            
            if (isAllDay) {
                // Extract date components from local time
                val localCal = java.util.Calendar.getInstance()
                localCal.time = startDate
                val startYear = localCal.get(java.util.Calendar.YEAR)
                val startMonth = localCal.get(java.util.Calendar.MONTH)
                val startDay = localCal.get(java.util.Calendar.DAY_OF_MONTH)
                
                localCal.time = endDate
                val endYear = localCal.get(java.util.Calendar.YEAR)
                val endMonth = localCal.get(java.util.Calendar.MONTH)
                val endDay = localCal.get(java.util.Calendar.DAY_OF_MONTH)
                
                // Create UTC timestamps with those date components
                val utcCal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
                utcCal.set(startYear, startMonth, startDay, 0, 0, 0)
                utcCal.set(java.util.Calendar.MILLISECOND, 0)
                startMillis = utcCal.timeInMillis
                
                utcCal.set(endYear, endMonth, endDay, 0, 0, 0)
                utcCal.set(java.util.Calendar.MILLISECOND, 0)
                endMillis = utcCal.timeInMillis
            } else {
                startMillis = startDate.time
                endMillis = endDate.time
            }
            
            val values = android.content.ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendarId.toLong())
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DTSTART, startMillis)
                put(CalendarContract.Events.DTEND, endMillis)
                put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
                
                // Set description if provided
                if (description != null) {
                    put(CalendarContract.Events.DESCRIPTION, description)
                }
                
                // Set location if provided
                if (location != null) {
                    put(CalendarContract.Events.EVENT_LOCATION, location)
                }
                
                // Set timezone
                // For all-day events, use device timezone to make them "floating"
                // This ensures the date components (year/month/day) stay the same
                // regardless of timezone changes
                if (isAllDay) {
                    put(CalendarContract.Events.EVENT_TIMEZONE, java.util.TimeZone.getDefault().id)
                } else {
                    // For non-all-day events, use provided timezone or default to device timezone
                    val tz = timeZone ?: java.util.TimeZone.getDefault().id
                    put(CalendarContract.Events.EVENT_TIMEZONE, tz)
                }
                
                // Map availability string to Android constant
                val availabilityValue = when (availability) {
                    "free" -> CalendarContract.Events.AVAILABILITY_FREE
                    "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
                    "unavailable" -> CalendarContract.Events.AVAILABILITY_BUSY
                    else -> CalendarContract.Events.AVAILABILITY_BUSY // "busy" or default
                }
                put(CalendarContract.Events.AVAILABILITY, availabilityValue)
                
                // Set status to confirmed
                put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CONFIRMED)
            }
            
            val uri = activity.contentResolver.insert(
                CalendarContract.Events.CONTENT_URI,
                values
            )
            
            if (uri != null) {
                val eventId = uri.lastPathSegment
                if (eventId != null) {
                    return Result.success(eventId)
                }
            }
            
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to create event: No event ID returned"
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
                    "Failed to create event: ${e.message}"
                )
            )
        }
    }
    
    fun deleteEvent(instanceId: String, deleteAllInstances: Boolean): Result<Unit> {
        // Check for write calendar permission
        if (android.content.pm.PackageManager.PERMISSION_GRANTED != 
            activity.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            // Parse instanceId: "eventId" or "eventId@timestamp"
            val parts = instanceId.split("@", limit = 2)
            val eventId = parts[0]
            
            if (parts.size == 2 && !deleteAllInstances) {
                // Deleting a single instance of a recurring event
                // This requires using the Instances table with a specific timestamp
                val occurrenceMillis = parts[1].toLongOrNull()
                if (occurrenceMillis == null) {
                    return Result.failure(
                        CalendarException(
                            PlatformExceptionCodes.INVALID_ARGUMENTS,
                            "Invalid instanceId format: $instanceId"
                        )
                    )
                }
                
                // For single instance deletion of recurring events, we need to query the specific instance
                // and delete it from the Instances table
                val deleteUri = ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_URI,
                    eventId.toLong()
                )
                
                // Note: Android doesn't easily support deleting single instances
                // We'll need to use CONTENT_EXCEPTION_URI or similar
                // For now, return an error indicating this is not fully supported
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.UNKNOWN_ERROR,
                        "Deleting single instances of recurring events is not yet fully supported. Set deleteAllInstances to true to delete the entire series."
                    )
                )
            } else {
                // Delete the event (or all instances if recurring)
                val deletedRows = activity.contentResolver.delete(
                    CalendarContract.Events.CONTENT_URI,
                    "${CalendarContract.Events._ID} = ?",
                    arrayOf(eventId)
                )
                
                if (deletedRows == 0) {
                    return Result.failure(
                        CalendarException(
                            PlatformExceptionCodes.INVALID_ARGUMENTS,
                            "Event with ID $eventId not found"
                        )
                    )
                }
                
                return Result.success(Unit)
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
                    "Failed to delete event: ${e.message}"
                )
            )
        }
    }
    
    fun updateEvent(
        instanceId: String,
        updateAllInstances: Boolean,
        title: String?,
        startDate: java.util.Date?,
        endDate: java.util.Date?,
        description: String?,
        location: String?,
        isAllDay: Boolean?,
        timeZone: String?,
        availability: String?
    ): Result<Unit> {
        // Check for write calendar permission
        if (android.content.pm.PackageManager.PERMISSION_GRANTED != 
            activity.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            // Parse instanceId: "eventId" or "eventId@timestamp"
            val parts = instanceId.split("@", limit = 2)
            val eventId = parts[0]
            
            // Check if this is a single instance update on a recurring event
            if (parts.size == 2 && !updateAllInstances) {
                // Updating a single instance of a recurring event is not fully supported
                // Similar limitation to deletion
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.UNKNOWN_ERROR,
                        "Updating single instances of recurring events is not yet fully supported. Set updateAllInstances to true to update the entire series."
                    )
                )
            }
            
            // Need to fetch existing event to determine if it's all-day
            // This is required for proper date normalization
            val existingEventResult = getEvent(instanceId)
            val existingEvent = existingEventResult.getOrNull()
            val wasAllDay = existingEvent?.get("isAllDay") as? Boolean ?: false
            
            // Build ContentValues with only provided fields
            val values = android.content.ContentValues()
            
            // Update title if provided
            if (title != null) {
                values.put(CalendarContract.Events.TITLE, title)
            }
            
            // Update description if provided
            if (description != null) {
                values.put(CalendarContract.Events.DESCRIPTION, description)
            }
            
            // Update location if provided
            if (location != null) {
                values.put(CalendarContract.Events.EVENT_LOCATION, location)
            }
            
            // Update isAllDay if provided
            val effectiveIsAllDay = isAllDay ?: wasAllDay
            if (isAllDay != null) {
                values.put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
            }
            
            // Update dates if provided
            // If event is/becomes all-day, need to normalize to UTC midnight
            if (startDate != null || endDate != null) {
                val startMillis: Long?
                val endMillis: Long?
                
                if (effectiveIsAllDay) {
                    // For all-day events, convert date components to UTC midnight
                    val localCal = java.util.Calendar.getInstance()
                    
                    if (startDate != null) {
                        localCal.time = startDate
                        val startYear = localCal.get(java.util.Calendar.YEAR)
                        val startMonth = localCal.get(java.util.Calendar.MONTH)
                        val startDay = localCal.get(java.util.Calendar.DAY_OF_MONTH)
                        
                        val utcCal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
                        utcCal.set(startYear, startMonth, startDay, 0, 0, 0)
                        utcCal.set(java.util.Calendar.MILLISECOND, 0)
                        startMillis = utcCal.timeInMillis
                    } else {
                        startMillis = null
                    }
                    
                    if (endDate != null) {
                        localCal.time = endDate
                        val endYear = localCal.get(java.util.Calendar.YEAR)
                        val endMonth = localCal.get(java.util.Calendar.MONTH)
                        val endDay = localCal.get(java.util.Calendar.DAY_OF_MONTH)
                        
                        val utcCal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
                        utcCal.set(endYear, endMonth, endDay, 0, 0, 0)
                        utcCal.set(java.util.Calendar.MILLISECOND, 0)
                        endMillis = utcCal.timeInMillis
                    } else {
                        endMillis = null
                    }
                } else {
                    // For timed events, use timestamps directly
                    startMillis = startDate?.time
                    endMillis = endDate?.time
                }
                
                if (startMillis != null) {
                    values.put(CalendarContract.Events.DTSTART, startMillis)
                }
                if (endMillis != null) {
                    values.put(CalendarContract.Events.DTEND, endMillis)
                }
            }
            
            // Update timezone if provided
            // Note: For all-day events, timezone should be set but is less relevant
            if (timeZone != null) {
                values.put(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
            } else if (isAllDay == true) {
                // If changing to all-day, set device timezone
                values.put(CalendarContract.Events.EVENT_TIMEZONE, java.util.TimeZone.getDefault().id)
            }
            
            // Update availability if provided
            if (availability != null) {
                val availabilityValue = when (availability) {
                    "free" -> CalendarContract.Events.AVAILABILITY_FREE
                    "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
                    "unavailable" -> CalendarContract.Events.AVAILABILITY_BUSY
                    else -> CalendarContract.Events.AVAILABILITY_BUSY // "busy" or default
                }
                values.put(CalendarContract.Events.AVAILABILITY, availabilityValue)
            }
            
            // Perform the update
            val updatedRows = activity.contentResolver.update(
                CalendarContract.Events.CONTENT_URI,
                values,
                "${CalendarContract.Events._ID} = ?",
                arrayOf(eventId)
            )
            
            if (updatedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "Event with ID $eventId not found"
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
                    "Failed to update event: ${e.message}"
                )
            )
        }
    }
}

