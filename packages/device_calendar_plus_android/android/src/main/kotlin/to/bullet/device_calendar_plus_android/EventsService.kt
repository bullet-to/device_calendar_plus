package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import java.util.Date

class EventsService(private val context: Context) {
    
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
            context.contentResolver.query(
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
        recurrenceRuleColumn: String,
        createdColumn: String? = null,
        lastModifiedColumn: String? = null
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
        val createdIndex = if (createdColumn != null) cursor.getColumnIndex(createdColumn) else -1
        val lastModifiedIndex = if (lastModifiedColumn != null) cursor.getColumnIndex(lastModifiedColumn) else -1
        
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
        val createdDate = if (createdIndex >= 0 && !cursor.isNull(createdIndex)) cursor.getLong(createdIndex) else null
        val lastModifiedDate = if (lastModifiedIndex >= 0 && !cursor.isNull(lastModifiedIndex)) cursor.getLong(lastModifiedIndex) else null
        
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
        
        // Set isRecurring flag and raw RRULE string
        eventMap["isRecurring"] = (recurrenceRule != null)
        if (recurrenceRule != null) {
            eventMap["recurrenceRule"] = recurrenceRule
        }
        
        // Add creation and modification dates if available
        if (createdDate != null) {
            eventMap["createdDate"] = createdDate
        }
        if (lastModifiedDate != null) {
            eventMap["updatedDate"] = lastModifiedDate
        }

        // Query attendees
        val attendees = queryAttendees(eventId.toLong())
        if (attendees.isNotEmpty()) {
            eventMap["attendees"] = attendees
        }

        return eventMap
    }

    private fun queryAttendees(eventId: Long): List<Map<String, Any?>> {
        val attendees = mutableListOf<Map<String, Any?>>()

        try {
            activity.contentResolver.query(
                CalendarContract.Attendees.CONTENT_URI,
                arrayOf(
                    CalendarContract.Attendees.ATTENDEE_NAME,
                    CalendarContract.Attendees.ATTENDEE_EMAIL,
                    CalendarContract.Attendees.ATTENDEE_TYPE,
                    CalendarContract.Attendees.ATTENDEE_RELATIONSHIP,
                    CalendarContract.Attendees.ATTENDEE_STATUS,
                ),
                "${CalendarContract.Attendees.EVENT_ID} = ?",
                arrayOf(eventId.toString()),
                null
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val relationship = cursor.getInt(
                        cursor.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_RELATIONSHIP)
                    )
                    // Skip the organizer
                    if (relationship == CalendarContract.Attendees.RELATIONSHIP_ORGANIZER) continue

                    val name = cursor.getString(
                        cursor.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_NAME)
                    )
                    val email = cursor.getString(
                        cursor.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_EMAIL)
                    )
                    val type = cursor.getInt(
                        cursor.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_TYPE)
                    )
                    val status = cursor.getInt(
                        cursor.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_STATUS)
                    )

                    attendees.add(mapOf(
                        "name" to name,
                        "emailAddress" to email,
                        "role" to attendeeTypeToRole(type),
                        "status" to attendeeStatusToString(status),
                    ))
                }
            }
        } catch (_: Exception) {
            // Silently return empty if attendee query fails
        }

        return attendees
    }

    private fun attendeeTypeToRole(type: Int): String {
        return when (type) {
            CalendarContract.Attendees.TYPE_REQUIRED -> "required"
            CalendarContract.Attendees.TYPE_OPTIONAL -> "optional"
            CalendarContract.Attendees.TYPE_RESOURCE -> "nonParticipant"
            else -> "required"
        }
    }

    private fun attendeeStatusToString(status: Int): String {
        return when (status) {
            CalendarContract.Attendees.ATTENDEE_STATUS_ACCEPTED -> "accepted"
            CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED -> "declined"
            CalendarContract.Attendees.ATTENDEE_STATUS_TENTATIVE -> "tentative"
            CalendarContract.Attendees.ATTENDEE_STATUS_INVITED -> "pending"
            else -> "none"
        }
    }
    
    fun getEvent(eventId: String, timestamp: Long?): Result<Map<String, Any>?> {
        if (timestamp != null) {
            // Recurring event with timestamp
            val occurrenceMillis = timestamp
            
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
                context.contentResolver.query(
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
    fun showEvent(activityContext: Activity, eventId: String, timestamp: Long?, requestCode: Int): Result<Unit> {
        return try {
            // Validate permissions
            if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
                context.checkSelfPermission(android.Manifest.permission.READ_CALENDAR)) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.PERMISSION_DENIED,
                        "Calendar permission denied. Call requestPermissions() first."
                    )
                )
            }
            
            val intent = Intent(Intent.ACTION_VIEW)
            
            // Build event URI
            val eventUri = android.content.ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI,
                eventId.toLong()
            )
            intent.data = eventUri
            
            // Add begin time for specific recurring event instances
            if (timestamp != null) {
                intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, timestamp)
            }
            
            // Use startActivityForResult to get a callback when the activity closes
            activityContext.startActivityForResult(intent, requestCode)
            Result.success(Unit)
        } catch (e: android.content.ActivityNotFoundException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.CALENDAR_UNAVAILABLE,
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
    
    /**
     * Opens native calendar editor in create mode with optional pre-fill.
     */
    fun showCreateEvent(
        activityContext: Activity,
        title: String?,
        startDate: Long?,
        endDate: Long?,
        description: String?,
        location: String?,
        isAllDay: Boolean?,
        recurrenceRule: String?,
        availability: String?,
        requestCode: Int,
    ): Result<Unit> {
        return try {
            if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
                context.checkSelfPermission(android.Manifest.permission.READ_CALENDAR)) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.PERMISSION_DENIED,
                        "Calendar permission denied. Call requestPermissions() first."
                    )
                )
            }

            val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)

            if (title != null) intent.putExtra(CalendarContract.Events.TITLE, title)
            if (description != null) intent.putExtra(CalendarContract.Events.DESCRIPTION, description)
            if (location != null) intent.putExtra(CalendarContract.Events.EVENT_LOCATION, location)
            if (startDate != null) intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startDate)
            if (endDate != null) intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endDate)
            if (isAllDay != null) intent.putExtra(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
            if (recurrenceRule != null) intent.putExtra(CalendarContract.Events.RRULE, recurrenceRule)
            if (availability != null) {
                val availabilityValue = when (availability) {
                    "free" -> CalendarContract.Events.AVAILABILITY_FREE
                    "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
                    else -> CalendarContract.Events.AVAILABILITY_BUSY
                }
                intent.putExtra(CalendarContract.Events.AVAILABILITY, availabilityValue)
            }

            activityContext.startActivityForResult(intent, requestCode)
            Result.success(Unit)
        } catch (e: android.content.ActivityNotFoundException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.CALENDAR_UNAVAILABLE,
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
                    "Failed to open create event modal: ${e.message}"
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
        availability: String,
        recurrenceRule: String?
    ): Result<String> {
        // Check for write calendar permission
        if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
            context.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
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
                put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
                
                // For recurring events, Android requires DURATION instead of DTEND
                if (recurrenceRule != null) {
                    val durationMillis = endMillis - startMillis
                    val durationSeconds = durationMillis / 1000
                    put(CalendarContract.Events.DURATION, "P${durationSeconds}S")
                    put(CalendarContract.Events.RRULE, recurrenceRule)
                } else {
                    put(CalendarContract.Events.DTEND, endMillis)
                }
                
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
            
            val uri = context.contentResolver.insert(
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
                    PlatformExceptionCodes.OPERATION_FAILED,
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
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to create event: ${e.message}"
                )
            )
        }
    }
    
    fun deleteEvent(eventId: String): Result<Unit> {
        // Check for write calendar permission
        if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
            context.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            // Delete the event (entire series for recurring events)
            val deletedRows = context.contentResolver.delete(
                CalendarContract.Events.CONTENT_URI,
                "${CalendarContract.Events._ID} = ?",
                arrayOf(eventId)
            )
            
            if (deletedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.NOT_FOUND,
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
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to delete event: ${e.message}"
                )
            )
        }
    }
    
    fun updateEvent(
        eventId: String,
        title: String?,
        startDate: java.util.Date?,
        endDate: java.util.Date?,
        description: String?,
        location: String?,
        isAllDay: Boolean?,
        timeZone: String?
    ): Result<Unit> {
        // Check for write calendar permission
        if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
            context.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }
        
        try {
            // Need to fetch existing event to determine if it's all-day
            // This is required for proper date normalization
            val existingEventResult = getEvent(eventId, null)
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
            
            // Perform the update
            val updatedRows = context.contentResolver.update(
                CalendarContract.Events.CONTENT_URI,
                values,
                "${CalendarContract.Events._ID} = ?",
                arrayOf(eventId)
            )
            
            if (updatedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.NOT_FOUND,
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
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to update event: ${e.message}"
                )
            )
        }
    }
}

