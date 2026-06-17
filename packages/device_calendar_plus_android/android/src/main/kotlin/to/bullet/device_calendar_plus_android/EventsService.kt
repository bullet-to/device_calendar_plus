package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import java.util.Date

private const val MINUTES_PER_DAY = 1440

// Default-calendar resolution reuses CalendarService rather than duplicating
// its cursor logic, so it's injected by the plugin.
class EventsService(
    private val context: Context,
    private val calendarService: CalendarService,
) {

    fun retrieveEvents(
        startDate: Date,
        endDate: Date,
        calendarIds: List<String>?,
        eventId: String? = null
    ): Result<List<Map<String, Any>>> {
        val events = mutableListOf<Map<String, Any>>()

        val startMillis = startDate.time
        val endMillis = endDate.time

        // All-day events are stored at UTC midnight boundaries, but the caller
        // passes local-midnight millis. We widen the Instances query to cover
        // UTC midnight boundaries too, then post-filter by date. (issue #20)
        val queryStartUtcMidnight = localMillisToUtcMidnight(startMillis)
        val queryEndUtcMidnight = localMillisToUtcMidnight(endMillis)

        val effectiveStart = minOf(startMillis, queryStartUtcMidnight)
        val effectiveEnd = maxOf(endMillis, queryEndUtcMidnight)

        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(effectiveStart.toString())
            .appendPath(effectiveEnd.toString())
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
            CalendarContract.Instances.RRULE,
            CalendarContract.Instances.CUSTOM_APP_URI
        )

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
                val beginIdx = cursor.getColumnIndex(CalendarContract.Instances.BEGIN)
                val endIdx = cursor.getColumnIndex(CalendarContract.Instances.END)
                val allDayIdx = cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY)

                while (cursor.moveToNext()) {
                    val eventBeginMillis = cursor.getLong(beginIdx)
                    val eventEndMillis = cursor.getLong(endIdx)
                    val isAllDay = cursor.getInt(allDayIdx) == 1

                    if (!isInRange(isAllDay, eventBeginMillis, eventEndMillis,
                            startMillis, endMillis, queryStartUtcMidnight, queryEndUtcMidnight)) {
                        continue
                    }

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
                        CalendarContract.Instances.RRULE,
                        urlColumn = CalendarContract.Instances.CUSTOM_APP_URI
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
    
    /**
     * Converts local millis to UTC midnight of the same local calendar date.
     * E.g. Dec 25 00:00 AEDT (UTC+11) → Dec 25 00:00 UTC.
     */
    private fun localMillisToUtcMidnight(millis: Long): Long = localDateToUtcMidnight(millis)

    /**
     * Checks whether an event (all-day or timed) falls within the query range.
     * All-day events are compared by UTC calendar date; timed events by millis.
     */
    private fun isInRange(
        isAllDay: Boolean,
        eventBegin: Long,
        eventEnd: Long,
        startMillis: Long,
        endMillis: Long,
        startUtcMidnight: Long,
        endUtcMidnight: Long
    ): Boolean {
        if (isAllDay) {
            // All-day BEGIN/END are UTC midnights. If end <= begin, it's a
            // single-day event stored without the +1 day convention.
            val effectiveEnd = if (eventEnd <= eventBegin) eventBegin + 86_400_000L else eventEnd
            return effectiveEnd > startUtcMidnight && eventBegin < endUtcMidnight
        }
        // Timed events: half-open overlap. A zero-duration (instantaneous) event
        // has no span, so give it a minimal effective end — otherwise one sitting
        // exactly on the query start fails `end > start` and is dropped. iOS
        // EventKit includes it. Mirrors the all-day effectiveEnd above.
        // See builttoroam/device_calendar#416.
        val effectiveEnd = if (eventEnd <= eventBegin) eventBegin + 1 else eventEnd
        return effectiveEnd > startMillis && eventBegin < endMillis
    }

    // A NULL column falls through to the documented "busy" default rather
    // than relying on 0 happening to be AVAILABILITY_BUSY.
    internal fun availabilityToString(availability: Int?): String {
        return when (availability) {
            CalendarContract.Events.AVAILABILITY_BUSY -> "busy"
            CalendarContract.Events.AVAILABILITY_FREE -> "free"
            CalendarContract.Events.AVAILABILITY_TENTATIVE -> "tentative"
            else -> "busy"
        }
    }
    
    // A NULL STATUS column means "no status", not 0 — and 0 is
    // STATUS_TENTATIVE, so defaulting the column would invent a status.
    internal fun statusToString(status: Int?): String {
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
        lastModifiedColumn: String? = null,
        urlColumn: String? = null
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
        val urlIndex = if (urlColumn != null) cursor.getColumnIndex(urlColumn) else -1
        
        val eventId = cursor.getString(eventIdIndex)
        val calendarId = cursor.getString(calendarIdIndex)
        val title = if (!cursor.isNull(titleIndex)) cursor.getString(titleIndex) else ""
        val description = if (!cursor.isNull(descriptionIndex)) cursor.getString(descriptionIndex) else null
        val location = if (!cursor.isNull(locationIndex)) cursor.getString(locationIndex) else null
        val rawStart = cursor.getLong(startIndex)
        val rawEnd = if (!cursor.isNull(endIndex)) cursor.getLong(endIndex) else rawStart
        val allDay = if (!cursor.isNull(allDayIndex)) cursor.getInt(allDayIndex) == 1 else false
        val availability = if (!cursor.isNull(availabilityIndex)) cursor.getInt(availabilityIndex) else null
        val status = if (!cursor.isNull(statusIndex)) cursor.getInt(statusIndex) else null
        val timeZone = if (!cursor.isNull(timeZoneIndex)) cursor.getString(timeZoneIndex) else null
        val recurrenceRule = if (!cursor.isNull(recurrenceRuleIndex)) cursor.getString(recurrenceRuleIndex) else null
        val createdDate = if (createdIndex >= 0 && !cursor.isNull(createdIndex)) cursor.getLong(createdIndex) else null
        val lastModifiedDate = if (lastModifiedIndex >= 0 && !cursor.isNull(lastModifiedIndex)) cursor.getLong(lastModifiedIndex) else null
        val url = if (urlIndex >= 0 && !cursor.isNull(urlIndex)) cursor.getString(urlIndex) else null
        
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
            start = utcToLocalMidnight(rawStart)
            end = utcToLocalMidnight(rawEnd)
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

        // Add URL if available (Android: CUSTOM_APP_URI)
        if (url != null) {
            eventMap["url"] = url
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
            context.contentResolver.query(
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
                CalendarContract.Events.RRULE,
                CalendarContract.Events.CUSTOM_APP_URI
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
                            CalendarContract.Events.RRULE,
                            urlColumn = CalendarContract.Events.CUSTOM_APP_URI
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
     * Shows a calendar event using the system calendar app.
     *
     * Fires [Intent.ACTION_VIEW] (details, with an edit button) or, when [edit]
     * is true, [Intent.ACTION_EDIT].
     *
     * Caveat: `ACTION_EDIT` is honored inconsistently by calendar apps. The
     * AOSP/stock calendar opens the existing event in its editor, but **Google
     * Calendar ignores the event URI and opens a blank new-event editor** — and
     * there is no intent that reliably launches it straight into edit mode on an
     * existing event. `ACTION_VIEW` (the [edit] == false path) binds to the
     * event everywhere, so a dependable edit flow is view-then-tap-edit.
     */
    fun showEvent(activityContext: Activity, eventId: String, timestamp: Long?, edit: Boolean, requestCode: Int): Result<Unit> {
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

            val intent = Intent(if (edit) Intent.ACTION_EDIT else Intent.ACTION_VIEW)
            
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
        calendarId: String?,
        title: String,
        startDate: java.util.Date,
        endDate: java.util.Date,
        isAllDay: Boolean,
        description: String?,
        location: String?,
        url: String?,
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
        
        // Resolve the target calendar. A null calendarId means "default
        // calendar" — resolve the primary (or first) writable calendar. The
        // resolver fails with permissionDenied if it can't read the calendar
        // list, so propagate that rather than flattening it into "no calendar".
        val resolvedCalendarId: String
        if (calendarId != null) {
            resolvedCalendarId = calendarId
        } else {
            val resolution = calendarService.resolveDefaultWritableCalendarId()
            resolution.exceptionOrNull()?.let { return Result.failure(it) }
            resolvedCalendarId = resolution.getOrNull() ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "No writable calendar available"
                )
            )
        }

        try {
            // For all-day events, Android interprets timestamps as UTC to determine the calendar date
            // We need to convert local date components to UTC midnight to preserve the calendar date
            val startMillis: Long
            val endMillis: Long
            
            if (isAllDay) {
                startMillis = localDateToUtcMidnight(startDate.time)
                endMillis = localDateToUtcMidnight(endDate.time)
            } else {
                startMillis = startDate.time
                endMillis = endDate.time
            }
            
            val values = android.content.ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, resolvedCalendarId.toLong())
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

                // Set URL if provided (Android stores it in CUSTOM_APP_URI)
                if (url != null) {
                    put(CalendarContract.Events.CUSTOM_APP_URI, url)
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
    
    /**
     * Deletes an event. With a [timestamp], removes only the occurrence at
     * that instant from its recurring series, as a cancelled exception;
     * without one, deletes the event itself (the whole series when
     * recurring).
     */
    fun deleteEvent(eventId: String, timestamp: Long? = null): Result<Unit> {
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

        return try {
            if (timestamp != null) {
                deleteEventInstance(eventId, timestamp)
            } else {
                deleteEventMaster(eventId)
            }
        } catch (e: SecurityException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to delete event: ${e.message}"
                )
            )
        }
    }

    /**
     * The bare-event-ID path of [deleteEvent]: deletes the event row itself —
     * the whole series when recurring.
     */
    private fun deleteEventMaster(eventId: String): Result<Unit> {
        // Use sync-adapter context so the Calendar Provider physically
        // removes the row instead of just setting DELETED=1. Without
        // this, the event survives deletion on real devices (where a
        // sync adapter is present) and getEvent still returns it.
        val uri = buildDeleteUri(eventId)
        val deletedRows = context.contentResolver.delete(
            uri,
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
    }
    
    /**
     * Updates an event. With a [timestamp], detaches the occurrence at that
     * instant from its recurring series and applies the changes to it alone;
     * without one, updates the event itself (the whole series when recurring).
     */
    fun updateEvent(
        eventId: String,
        timestamp: Long?,
        startDate: java.util.Date?,
        endDate: java.util.Date?,
        patch: EventFieldPatch
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

        return try {
            if (timestamp != null) {
                updateEventInstance(eventId, timestamp, startDate, endDate, patch)
            } else {
                updateEventMaster(eventId, startDate, endDate, patch)
            }
        } catch (e: SecurityException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to update event: ${e.message}"
                )
            )
        }
    }

    /**
     * The bare-event-ID path of [updateEvent]: updates the event row itself —
     * the whole series when recurring.
     */
    private fun updateEventMaster(
        eventId: String,
        startDate: java.util.Date?,
        endDate: java.util.Date?,
        patch: EventFieldPatch
    ): Result<Unit> {
        // The existing row decides all-day date normalization when the call
        // doesn't change the flag.
        val row = readEventRow(eventId)
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )

        // Build ContentValues with only provided fields
        val values = android.content.ContentValues()
        applyEventFieldValues(values, patch)

        // Update dates if provided
        // If event is/becomes all-day, need to normalize to UTC midnight
        val effectiveIsAllDay = patch.isAllDay ?: row.allDay
        if (startDate != null || endDate != null) {
            val startMillis: Long?
            val endMillis: Long?

            if (effectiveIsAllDay) {
                startMillis = startDate?.let { localDateToUtcMidnight(it.time) }
                endMillis = endDate?.let { localDateToUtcMidnight(it.time) }
            } else {
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
        if (patch.timeZone != null) {
            values.put(CalendarContract.Events.EVENT_TIMEZONE, patch.timeZone)
        } else if (patch.isAllDay == true) {
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
    }

    /**
     * Applies [patch] — title, description, location, url, all-day flag and
     * availability — to [values]. Fields named in the patch's clearedFields
     * are nulled; null fields are left untouched. The patch's time zone is
     * not applied here: each write path handles it differently.
     */
    private fun applyEventFieldValues(
        values: android.content.ContentValues,
        patch: EventFieldPatch
    ) {
        if (patch.title != null) {
            values.put(CalendarContract.Events.TITLE, patch.title)
        }
        if ("description" in patch.clearedFields) {
            values.putNull(CalendarContract.Events.DESCRIPTION)
        } else if (patch.description != null) {
            values.put(CalendarContract.Events.DESCRIPTION, patch.description)
        }
        if ("location" in patch.clearedFields) {
            values.putNull(CalendarContract.Events.EVENT_LOCATION)
        } else if (patch.location != null) {
            values.put(CalendarContract.Events.EVENT_LOCATION, patch.location)
        }
        if ("url" in patch.clearedFields) {
            values.putNull(CalendarContract.Events.CUSTOM_APP_URI)
        } else if (patch.url != null) {
            values.put(CalendarContract.Events.CUSTOM_APP_URI, patch.url)
        }
        if (patch.isAllDay != null) {
            values.put(CalendarContract.Events.ALL_DAY, if (patch.isAllDay) 1 else 0)
        }
        if (patch.availability != null) {
            values.put(
                CalendarContract.Events.AVAILABILITY,
                availabilityToInt(patch.availability)
            )
        }
    }

    /**
     * Detaches the occurrence at [timestamp] from its recurring series as an
     * exception and applies the changes to it alone. The instance-ID path of
     * [updateEvent]; [startDate] and [endDate] are absolute instants, so the
     * occurrence can move to a different day.
     */
    private fun updateEventInstance(
        eventId: String,
        timestamp: Long,
        startDate: java.util.Date?,
        endDate: java.util.Date?,
        patch: EventFieldPatch
    ): Result<Unit> {
        val row = readEventRow(eventId)
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )

        if (row.rrule == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "Event $eventId is not recurring; pass a bare event ID instead"
                )
            )
        }

        val effectiveIsAllDay = patch.isAllDay ?: row.allDay
        val newStart = if (startDate != null) {
            toStorageMillis(startDate, effectiveIsAllDay)
        } else {
            timestamp
        }
        // Without an explicit endDate the occurrence's own end stays put —
        // matching iOS, where setting startDate leaves endDate untouched.
        val newEnd = if (endDate != null) {
            toStorageMillis(endDate, effectiveIsAllDay)
        } else {
            timestamp + eventDurationMillis(row)
        }
        if (newEnd <= newStart) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "End date must be after the occurrence's start date"
                )
            )
        }

        // Insert an exception overriding this single occurrence. The provider
        // expects DURATION (not DTEND) on an exception of a recurring parent.
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, timestamp)
            put(CalendarContract.Events.DTSTART, newStart)
            put(CalendarContract.Events.DURATION, "P${(newEnd - newStart) / 1000}S")
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CONFIRMED)
        }
        applyEventFieldValues(values, patch)
        if (patch.timeZone != null) {
            values.put(CalendarContract.Events.EVENT_TIMEZONE, patch.timeZone)
        }

        val exceptionUri = android.content.ContentUris.withAppendedId(
            CalendarContract.Events.CONTENT_EXCEPTION_URI,
            eventId.toLong()
        )
        val uri = context.contentResolver.insert(exceptionUri, values)
        if (uri?.lastPathSegment == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to create the exception for event $eventId"
                )
            )
        }
        return Result.success(Unit)
    }

    // -- updateRecurring (issue #36) --

    /**
     * Updates a recurring event's series, choosing which occurrences the edit
     * affects.
     *
     * [span] is "allEvents" (the whole series) or "thisAndFollowing" (split
     * the series at [timestamp], that occurrence onward forming the new
     * series). Single-occurrence edits go through [updateEvent] with a
     * timestamp. Returns the event ID for the affected scope.
     */
    fun updateRecurring(
        eventId: String,
        timestamp: Long?,
        span: String,
        newStartMillis: Long?,
        durationMinutes: Int?,
        recurrenceRule: String?,
        patch: EventFieldPatch
    ): Result<String> {
        if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
            context.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }

        return try {
            if (span != "allEvents" && span != "thisAndFollowing") {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "Unknown update span: $span"
                    )
                )
            }

            val row = readEventRow(eventId)
                ?: return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.NOT_FOUND,
                        "Event with ID $eventId not found"
                    )
                )

            // All-day events have no time-of-day and only whole-day durations.
            // The Dart layer can only check these against fields in the same
            // call; the stored event's state is enforced here.
            val effectiveIsAllDay = patch.isAllDay ?: row.allDay
            if (durationMinutes != null && effectiveIsAllDay &&
                durationMinutes % MINUTES_PER_DAY != 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "All-day events require whole-day durations"
                    )
                )
            }

            // A `start` that moves the day of a series whose rule pins that day
            // explicitly is ambiguous (see updateRecurring docs) — refuse it
            // unless the caller also supplies the new rule. Implicit rules (no
            // BYDAY/BYMONTHDAY) just follow the anchor, so they pass through.
            val changingRule = recurrenceRule != null ||
                "recurrenceRule" in patch.clearedFields
            if (newStartMillis != null && !changingRule && row.rrule != null &&
                dayMoveConflictsWithRule(
                    row.rrule, timestamp ?: row.dtstart, newStartMillis, row.timeZone
                )
            ) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "start moves this series to a different day, but its " +
                            "recurrence rule pins specific days. Pass a " +
                            "recurrenceRule to specify the new pattern."
                    )
                )
            }

            when (span) {
                "thisAndFollowing" -> updateRecurringThisAndFollowing(
                    eventId, row, timestamp, newStartMillis,
                    durationMinutes, recurrenceRule, patch
                )
                else -> updateRecurringAllEvents(
                    eventId, row, timestamp, newStartMillis,
                    durationMinutes, recurrenceRule, patch
                )
            }
        } catch (e: SecurityException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to update recurring event: ${e.message}"
                )
            )
        }
    }

    private fun updateRecurringAllEvents(
        eventId: String,
        row: EventRow,
        timestamp: Long?,
        newStartMillis: Long?,
        durationMinutes: Int?,
        recurrenceRule: String?,
        patch: EventFieldPatch
    ): Result<String> {
        val values = android.content.ContentValues()
        applyEventFieldValues(values, patch)

        // Recurrence rule column and the resulting recurring state.
        val wasRecurring = row.rrule != null
        val clearRrule = "recurrenceRule" in patch.clearedFields
        val willBeRecurring = when {
            clearRrule -> false
            recurrenceRule != null -> true
            else -> wasRecurring
        }
        if (clearRrule) {
            values.putNull(CalendarContract.Events.RRULE)
        } else if (recurrenceRule != null) {
            values.put(CalendarContract.Events.RRULE, recurrenceRule)
        }

        // Time columns. A recurring event must use DURATION (and no DTEND); a
        // single event must use DTEND (and no DURATION). Rewrite them when the
        // start, duration, or recurring state changes.
        val effectiveIsAllDay = patch.isAllDay ?: row.allDay
        val hasTimeChange = newStartMillis != null || durationMinutes != null
        if (hasTimeChange || wasRecurring != willBeRecurring) {
            // The anchor shifts relative to the occurrence the caller pointed
            // at (timestamp), or the series anchor itself when none was given.
            val (newStart, newDurationMs) = resolveSeriesTimes(
                row.dtstart, timestamp ?: row.dtstart, eventDurationMillis(row),
                newStartMillis, durationMinutes, row.timeZone, effectiveIsAllDay
            )
            values.put(CalendarContract.Events.DTSTART, newStart)
            if (willBeRecurring) {
                values.put(
                    CalendarContract.Events.DURATION,
                    "P${newDurationMs / 1000}S"
                )
                values.putNull(CalendarContract.Events.DTEND)
                // Moving DTSTART alone doesn't reliably invalidate the
                // Instances cache, so the series can read back as a single
                // occurrence. Re-writing the (unchanged) RRULE forces the
                // CalendarProvider to re-expand — the mirror of the
                // DTSTART/DURATION rewrite used when only the rule changes.
                if (!clearRrule && recurrenceRule == null && row.rrule != null) {
                    values.put(CalendarContract.Events.RRULE, row.rrule)
                }
            } else {
                values.put(CalendarContract.Events.DTEND, newStart + newDurationMs)
                values.putNull(CalendarContract.Events.DURATION)
            }
        }

        if (patch.timeZone != null) {
            values.put(CalendarContract.Events.EVENT_TIMEZONE, patch.timeZone)
        } else if (patch.isAllDay == true) {
            values.put(
                CalendarContract.Events.EVENT_TIMEZONE,
                java.util.TimeZone.getDefault().id
            )
        }

        // RRULE writes require sync-adapter context on Android — see
        // updateEventAsSyncAdapter for the rationale.
        val updatedRows = updateEventAsSyncAdapter(eventId, row.calendarId, values)
        if (updatedRows == 0) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )
        }
        return Result.success(eventId)
    }

    private fun updateRecurringThisAndFollowing(
        eventId: String,
        row: EventRow,
        timestamp: Long?,
        newStartMillis: Long?,
        durationMinutes: Int?,
        recurrenceRule: String?,
        patch: EventFieldPatch
    ): Result<String> {
        if (timestamp == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "thisAndFollowing requires an occurrence timestamp"
                )
            )
        }

        if (row.rrule == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "Event $eventId is not recurring; use updateEvent instead"
                )
            )
        }

        // Effective field values for the new series: the patch value when one
        // is given, otherwise the master's existing value.
        val effectiveIsAllDay = patch.isAllDay ?: row.allDay
        val effectiveTitle = patch.title ?: row.title
        val effectiveDescription = if ("description" in patch.clearedFields) {
            null
        } else {
            patch.description ?: row.description
        }
        val effectiveLocation = if ("location" in patch.clearedFields) {
            null
        } else {
            patch.location ?: row.location
        }
        val effectiveUrl =
            if ("url" in patch.clearedFields) null else (patch.url ?: row.url)
        val effectiveTimeZone = patch.timeZone ?: row.timeZone
        val effectiveAvailability = patch.availability ?: row.availability
        val effectiveRrule = when {
            "recurrenceRule" in patch.clearedFields -> null
            recurrenceRule != null -> recurrenceRule
            else -> {
                // Rule unchanged: the new series inherits the original rule. A
                // COUNT must drop by the occurrences left on the old series,
                // or the new series would over-generate.
                val originalCount = rruleCount(row.rrule)
                if (originalCount != null) {
                    val before = countInstancesBefore(eventId, timestamp)
                    setRruleCount(row.rrule, maxOf(1, originalCount - before))
                } else {
                    row.rrule
                }
            }
        }

        // The new series is anchored at the split occurrence, shifted to the
        // caller's new start (the reference and base are both the occurrence).
        // Duration is the master's unless overridden.
        val (newStart, newDurationMs) = resolveSeriesTimes(
            timestamp, timestamp, eventDurationMillis(row),
            newStartMillis, durationMinutes, row.timeZone, effectiveIsAllDay
        )
        val newEnd = newStart + newDurationMs

        // Create the new series first, so that a later failure leaves the
        // original series intact.
        val insertResult = insertEvent(
            calendarId = row.calendarId,
            title = effectiveTitle,
            startMillis = newStart,
            endMillis = newEnd,
            isAllDay = effectiveIsAllDay,
            description = effectiveDescription,
            location = effectiveLocation,
            url = effectiveUrl,
            timeZone = effectiveTimeZone,
            availability = effectiveAvailability,
            rrule = effectiveRrule
        )
        val newEventId = insertResult.getOrElse { return Result.failure(it) }

        // Truncate the original series to end just before the anchor. UNTIL is
        // inclusive, so cutting it one second early keeps the anchor occurrence
        // off the old series — it belongs to the new one.
        //
        // RRULE writes go through updateEventAsSyncAdapter; we also rewrite
        // DTSTART/DURATION with their existing values to force Android's
        // CalendarProvider to invalidate the Instances cache (it doesn't
        // always when only RRULE changes — see deleteRecurringThisAndFollowing).
        val truncatedRrule = setRruleUntil(row.rrule, timestamp - 1000, row.allDay)
        val truncateValues = android.content.ContentValues().apply {
            put(CalendarContract.Events.RRULE, truncatedRrule)
            put(CalendarContract.Events.DTSTART, row.dtstart)
            if (row.duration != null) {
                put(CalendarContract.Events.DURATION, row.duration)
            }
        }
        val truncatedRows =
            updateEventAsSyncAdapter(eventId, row.calendarId, truncateValues)
        if (truncatedRows == 0) {
            // Roll back the new series so the calendar is left unchanged.
            context.contentResolver.delete(
                CalendarContract.Events.CONTENT_URI,
                "${CalendarContract.Events._ID} = ?",
                arrayOf(newEventId)
            )
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to truncate original series for event $eventId"
                )
            )
        }

        return Result.success(newEventId)
    }

    // -- deleteRecurring (issue #43) --

    /**
     * Deletes a recurring event's series, choosing which occurrences are
     * removed.
     *
     * [span] is "allEvents" (the whole series) or "thisAndFollowing" (the
     * occurrence at [timestamp] and every later one, truncating the series
     * before it). Single-occurrence deletes go through [deleteEvent] with a
     * timestamp.
     */
    fun deleteRecurring(
        eventId: String,
        timestamp: Long?,
        span: String
    ): Result<Unit> {
        if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
            context.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied. Call requestPermissions() first."
                )
            )
        }

        return try {
            when (span) {
                "allEvents" -> deleteEvent(eventId)
                "thisAndFollowing" -> deleteRecurringThisAndFollowing(eventId, timestamp)
                else -> Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "Unknown delete span: $span"
                    )
                )
            }
        } catch (e: SecurityException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to delete recurring event: ${e.message}"
                )
            )
        }
    }

    private fun deleteRecurringThisAndFollowing(
        eventId: String,
        timestamp: Long?
    ): Result<Unit> {
        if (timestamp == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "thisAndFollowing requires an occurrence timestamp"
                )
            )
        }

        val row = readEventRow(eventId)
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )

        if (row.rrule == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "Event $eventId is not recurring; use deleteEvent instead"
                )
            )
        }

        // Truncate the series so the anchor occurrence and every later one
        // stop generating. UNTIL is inclusive, so cutting one second early
        // drops the anchor too — "this and following" removes the anchor.
        //
        // RRULE writes go through updateEventAsSyncAdapter; we also rewrite
        // DTSTART/DURATION with their existing values, because Android's
        // CalendarProvider doesn't always invalidate the Instances cache
        // when only RRULE changes — touching multiple time columns forces
        // it to regenerate. Without this the master's RRULE is correctly
        // updated on disk but listEvents keeps returning the old expansion.
        val truncatedRrule = setRruleUntil(row.rrule, timestamp - 1000, row.allDay)
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.RRULE, truncatedRrule)
            put(CalendarContract.Events.DTSTART, row.dtstart)
            if (row.duration != null) {
                put(CalendarContract.Events.DURATION, row.duration)
            }
        }
        val updatedRows = updateEventAsSyncAdapter(eventId, row.calendarId, values)
        if (updatedRows == 0) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )
        }
        return Result.success(Unit)
    }

    /**
     * The instance-ID path of [deleteEvent]: removes the single occurrence
     * at [timestamp] by inserting a cancelled exception event via
     * CONTENT_EXCEPTION_URI. The Calendar Provider then excludes that
     * occurrence from the Instances expansion.
     */
    private fun deleteEventInstance(
        eventId: String,
        timestamp: Long
    ): Result<Unit> {
        val row = readEventRow(eventId)
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )

        if (row.rrule == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "Event $eventId is not recurring; pass a bare event ID instead"
                )
            )
        }

        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, timestamp)
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CANCELED)
        }

        // Build the exception URI with sync-adapter context.
        val account = readCalendarAccount(row.calendarId)
        val uriBuilder = CalendarContract.Events.CONTENT_EXCEPTION_URI.buildUpon()
        if (account != null) {
            uriBuilder
                .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                .appendQueryParameter(CalendarContract.Events.ACCOUNT_NAME, account.first)
                .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, account.second)
        }
        uriBuilder.appendPath(eventId)

        val exceptionUri = context.contentResolver.insert(uriBuilder.build(), values)
        if (exceptionUri == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to create cancellation exception for event $eventId"
                )
            )
        }
        return Result.success(Unit)
    }

    private data class EventRow(
        val id: String,
        val calendarId: String,
        val title: String,
        val description: String?,
        val location: String?,
        val url: String?,
        val dtstart: Long,
        val dtend: Long?,
        val duration: String?,
        val allDay: Boolean,
        val timeZone: String?,
        val availability: String,
        val rrule: String?
    )

    /** Reads the master row of an event straight from the Events table. */
    private fun readEventRow(eventId: String): EventRow? {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CALENDAR_ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.CUSTOM_APP_URI,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.DURATION,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.EVENT_TIMEZONE,
            CalendarContract.Events.AVAILABILITY,
            CalendarContract.Events.RRULE
        )
        context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            fun str(column: String): String? {
                val index = cursor.getColumnIndexOrThrow(column)
                return if (cursor.isNull(index)) null else cursor.getString(index)
            }
            fun long(column: String): Long? {
                val index = cursor.getColumnIndexOrThrow(column)
                return if (cursor.isNull(index)) null else cursor.getLong(index)
            }
            return EventRow(
                id = str(CalendarContract.Events._ID) ?: eventId,
                calendarId = str(CalendarContract.Events.CALENDAR_ID) ?: "",
                title = str(CalendarContract.Events.TITLE) ?: "",
                description = str(CalendarContract.Events.DESCRIPTION),
                location = str(CalendarContract.Events.EVENT_LOCATION),
                url = str(CalendarContract.Events.CUSTOM_APP_URI),
                dtstart = long(CalendarContract.Events.DTSTART) ?: 0L,
                dtend = long(CalendarContract.Events.DTEND),
                duration = str(CalendarContract.Events.DURATION),
                allDay = (long(CalendarContract.Events.ALL_DAY) ?: 0L) == 1L,
                timeZone = str(CalendarContract.Events.EVENT_TIMEZONE),
                availability = availabilityToString(
                    long(CalendarContract.Events.AVAILABILITY)?.toInt()
                ),
                rrule = str(CalendarContract.Events.RRULE)
            )
        }
        return null
    }

    /** Inserts a fresh event row, using DURATION when recurring and DTEND otherwise. */
    private fun insertEvent(
        calendarId: String,
        title: String,
        startMillis: Long,
        endMillis: Long,
        isAllDay: Boolean,
        description: String?,
        location: String?,
        url: String?,
        timeZone: String?,
        availability: String,
        rrule: String?
    ): Result<String> {
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId.toLong())
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DTSTART, startMillis)
            put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
            if (rrule != null) {
                put(
                    CalendarContract.Events.DURATION,
                    "P${(endMillis - startMillis) / 1000}S"
                )
                put(CalendarContract.Events.RRULE, rrule)
            } else {
                put(CalendarContract.Events.DTEND, endMillis)
            }
            if (description != null) {
                put(CalendarContract.Events.DESCRIPTION, description)
            }
            if (location != null) {
                put(CalendarContract.Events.EVENT_LOCATION, location)
            }
            if (url != null) {
                put(CalendarContract.Events.CUSTOM_APP_URI, url)
            }
            put(
                CalendarContract.Events.EVENT_TIMEZONE,
                if (isAllDay) java.util.TimeZone.getDefault().id
                else (timeZone ?: java.util.TimeZone.getDefault().id)
            )
            put(CalendarContract.Events.AVAILABILITY, availabilityToInt(availability))
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CONFIRMED)
        }
        val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
        val newId = uri?.lastPathSegment
        return if (newId != null) {
            Result.success(newId)
        } else {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to create the new series"
                )
            )
        }
    }

    private fun availabilityToInt(availability: String): Int {
        return when (availability) {
            "free" -> CalendarContract.Events.AVAILABILITY_FREE
            "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
            else -> CalendarContract.Events.AVAILABILITY_BUSY
        }
    }

    /**
     * Resolves the start and duration for a series-level time edit. When
     * [newStartMillis] is given the start is shifted by the wall-clock delta
     * from [referenceMillis] to [newStartMillis] (see [shiftDate]); the
     * duration is overridden when [durationMinutes] is given.
     */
    private fun resolveSeriesTimes(
        baseMillis: Long,
        referenceMillis: Long,
        existingDurationMillis: Long,
        newStartMillis: Long?,
        durationMinutes: Int?,
        timeZoneId: String?,
        isAllDay: Boolean
    ): Pair<Long, Long> {
        val newStart = if (newStartMillis != null) {
            shiftDate(baseMillis, referenceMillis, newStartMillis, timeZoneId, isAllDay)
        } else {
            baseMillis
        }
        val newDurationMs = if (durationMinutes != null) {
            durationMinutes.toLong() * 60_000L
        } else {
            existingDurationMillis
        }
        return Pair(newStart, newDurationMs)
    }

    /**
     * Translates [baseMillis] by the wall-clock delta from [referenceMillis]
     * to [newStartMillis]: shifts by the whole-day difference and sets the
     * time-of-day to [newStartMillis]'s. DST-safe — it counts calendar days
     * and sets a wall-clock time rather than adding a raw interval.
     *
     * Dates are interpreted in the event's timezone (device default when
     * [timeZoneId] is null). All-day events are stored as UTC midnight, so
     * they shift in UTC by whole days with the time-of-day left at midnight.
     * The anchor-shift that lets [updateRecurring] move both the time and the
     * day of a series (issue #103); iOS's counterpart is `shiftStart`.
     */
    private fun shiftDate(
        baseMillis: Long,
        referenceMillis: Long,
        newStartMillis: Long,
        timeZoneId: String?,
        isAllDay: Boolean
    ): Long {
        val tz = when {
            isAllDay -> java.util.TimeZone.getTimeZone("UTC")
            timeZoneId != null -> java.util.TimeZone.getTimeZone(timeZoneId)
            else -> java.util.TimeZone.getDefault()
        }
        val dayDelta = calendarDaysBetween(referenceMillis, newStartMillis, tz)
        val cal = java.util.Calendar.getInstance(tz)
        cal.timeInMillis = baseMillis
        cal.add(java.util.Calendar.DAY_OF_YEAR, dayDelta)
        if (isAllDay) {
            cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
            cal.set(java.util.Calendar.MINUTE, 0)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
        } else {
            // Carry the full wall-clock time-of-day (down to millis) from the
            // target, matching iOS's shiftStart so the platforms agree.
            val target = java.util.Calendar.getInstance(tz)
            target.timeInMillis = newStartMillis
            cal.set(java.util.Calendar.HOUR_OF_DAY, target.get(java.util.Calendar.HOUR_OF_DAY))
            cal.set(java.util.Calendar.MINUTE, target.get(java.util.Calendar.MINUTE))
            cal.set(java.util.Calendar.SECOND, target.get(java.util.Calendar.SECOND))
            cal.set(java.util.Calendar.MILLISECOND, target.get(java.util.Calendar.MILLISECOND))
        }
        return cal.timeInMillis
    }

    /**
     * Whether moving the anchor from [referenceMillis] to [targetMillis] would
     * change the day-spec that [rrule] pins explicitly: the weekday for a
     * BYDAY rule, the day-of-month for a BYMONTHDAY rule, or the month for a
     * BYMONTH rule. When it would, an anchor shift alone can't say what the new
     * pattern should be (see updateRecurring docs), so the caller must supply a
     * new rule. Rules with no explicit anchor return false — they follow the
     * anchor freely. iOS's counterpart is `dayMoveConflictsWithRule`.
     */
    private fun dayMoveConflictsWithRule(
        rrule: String,
        referenceMillis: Long,
        targetMillis: Long,
        timeZoneId: String?
    ): Boolean {
        val hasByDay = rruleHasPart(rrule, "BYDAY")
        val hasByMonthDay = rruleHasPart(rrule, "BYMONTHDAY")
        val hasByMonth = rruleHasPart(rrule, "BYMONTH")
        if (!hasByDay && !hasByMonthDay && !hasByMonth) return false
        val tz = if (timeZoneId != null) java.util.TimeZone.getTimeZone(timeZoneId)
                 else java.util.TimeZone.getDefault()
        val ref = java.util.Calendar.getInstance(tz).apply { timeInMillis = referenceMillis }
        val tgt = java.util.Calendar.getInstance(tz).apply { timeInMillis = targetMillis }
        fun changed(field: Int) = ref.get(field) != tgt.get(field)
        if (hasByDay && changed(java.util.Calendar.DAY_OF_WEEK)) return true
        if (hasByMonthDay && changed(java.util.Calendar.DAY_OF_MONTH)) return true
        if (hasByMonth && changed(java.util.Calendar.MONTH)) return true
        return false
    }

    /**
     * Whole calendar days from [fromMillis] to [toMillis] in [tz]. Rounds the
     * start-of-day difference so a DST transition (a 23- or 25-hour day) still
     * yields an integer day count.
     */
    private fun calendarDaysBetween(
        fromMillis: Long,
        toMillis: Long,
        tz: java.util.TimeZone
    ): Int {
        fun startOfDay(millis: Long): Long {
            val c = java.util.Calendar.getInstance(tz)
            c.timeInMillis = millis
            c.set(java.util.Calendar.HOUR_OF_DAY, 0)
            c.set(java.util.Calendar.MINUTE, 0)
            c.set(java.util.Calendar.SECOND, 0)
            c.set(java.util.Calendar.MILLISECOND, 0)
            return c.timeInMillis
        }
        val diff = startOfDay(toMillis) - startOfDay(fromMillis)
        return Math.round(diff.toDouble() / 86_400_000.0).toInt()
    }

    /** Storage millis for a date: UTC midnight for all-day, the instant otherwise. */
    private fun toStorageMillis(date: java.util.Date, isAllDay: Boolean): Long {
        if (!isAllDay) return date.time
        return localDateToUtcMidnight(date.time)
    }

    /**
     * Converts local-time millis to UTC midnight, preserving the calendar date.
     * Used when writing all-day events: Android stores them as UTC midnight
     * boundaries, so a local "June 5" must become "June 5 00:00 UTC".
     */
    private fun localDateToUtcMidnight(localMillis: Long): Long {
        val local = java.util.Calendar.getInstance()
        local.timeInMillis = localMillis
        val utc = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        utc.set(
            local.get(java.util.Calendar.YEAR),
            local.get(java.util.Calendar.MONTH),
            local.get(java.util.Calendar.DAY_OF_MONTH),
            0, 0, 0
        )
        utc.set(java.util.Calendar.MILLISECOND, 0)
        return utc.timeInMillis
    }

    /**
     * Converts UTC millis to local midnight, preserving the calendar date.
     * Used when reading all-day events: Android stores them as UTC midnight
     * boundaries, and we need to present the date in the device's local time.
     */
    private fun utcToLocalMidnight(utcMillis: Long): Long {
        val utcCal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        utcCal.timeInMillis = utcMillis
        val localCal = java.util.Calendar.getInstance()
        localCal.set(
            utcCal.get(java.util.Calendar.YEAR),
            utcCal.get(java.util.Calendar.MONTH),
            utcCal.get(java.util.Calendar.DAY_OF_MONTH),
            0, 0, 0
        )
        localCal.set(java.util.Calendar.MILLISECOND, 0)
        return localCal.timeInMillis
    }

    /** Resolves an event's duration, falling back to one hour when unknown. */
    private fun eventDurationMillis(row: EventRow): Long {
        if (row.dtend != null) return row.dtend - row.dtstart
        if (row.duration != null) {
            parseDurationMillis(row.duration)?.let { return it }
        }
        return 3_600_000L
    }

    /** Parses an RFC 5545 / Android duration string (e.g. "P3600S", "PT1H"). */
    private fun parseDurationMillis(duration: String): Long? {
        val trimmed = duration.trim()
        Regex("P(\\d+)S").matchEntire(trimmed)?.let {
            return it.groupValues[1].toLong() * 1000L
        }
        val match = Regex(
            "P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?"
        ).matchEntire(trimmed) ?: return null
        var seconds = 0L
        match.groupValues[1].toLongOrNull()?.let { seconds += it * 7 * 24 * 3600 }
        match.groupValues[2].toLongOrNull()?.let { seconds += it * 24 * 3600 }
        match.groupValues[3].toLongOrNull()?.let { seconds += it * 3600 }
        match.groupValues[4].toLongOrNull()?.let { seconds += it * 60 }
        match.groupValues[5].toLongOrNull()?.let { seconds += it }
        return seconds * 1000L
    }

    /** Number of occurrences of [eventId] that start before [beforeMillis]. */
    private fun countInstancesBefore(eventId: String, beforeMillis: Long): Int {
        // Five-year look-back window: covers daily/weekly/monthly easily, and
        // yearly rules with an interval of up to five.
        val windowStart = beforeMillis - 5L * 366 * 24 * 3600 * 1000
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(windowStart.toString())
            .appendPath(beforeMillis.toString())
            .build()
        var count = 0
        context.contentResolver.query(
            uri,
            arrayOf(CalendarContract.Instances.BEGIN),
            "${CalendarContract.Instances.EVENT_ID} = ?",
            arrayOf(eventId),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getLong(0) < beforeMillis) count++
            }
        }
        return count
    }

    /**
     * Whether [rrule] carries the part named [key] (e.g. "BYDAY"). Matches on
     * the part key rather than a raw substring, so "BYMONTH" doesn't spuriously
     * match "BYMONTHDAY". Mirrors the key parsing in [rruleCount]/[setRruleUntil].
     */
    private fun rruleHasPart(rrule: String, key: String): Boolean {
        val body = if (rrule.startsWith("RRULE:")) rrule.substring(6) else rrule
        return body.split(";").any {
            it.substringBefore('=').uppercase() == key
        }
    }

    /** The COUNT value of an RRULE, or null if it has none. */
    private fun rruleCount(rrule: String): Int? {
        val body = if (rrule.startsWith("RRULE:")) rrule.substring(6) else rrule
        for (part in body.split(";")) {
            if (part.substringBefore('=').uppercase() == "COUNT") {
                return part.substringAfter('=').trim().toIntOrNull()
            }
        }
        return null
    }

    /** Replaces any COUNT/UNTIL in [rrule] with COUNT=[count]. */
    private fun setRruleCount(rrule: String, count: Int): String {
        val body = if (rrule.startsWith("RRULE:")) rrule.substring(6) else rrule
        val parts = body.split(";").filter {
            val key = it.substringBefore('=').uppercase()
            it.isNotEmpty() && key != "COUNT" && key != "UNTIL"
        }
        return (parts + "COUNT=$count").joinToString(";")
    }

    /** Replaces any COUNT/UNTIL in [rrule] with UNTIL at [untilMillis] (inclusive). */
    private fun setRruleUntil(rrule: String, untilMillis: Long, isAllDay: Boolean): String {
        val body = if (rrule.startsWith("RRULE:")) rrule.substring(6) else rrule
        val parts = body.split(";").filter {
            val key = it.substringBefore('=').uppercase()
            it.isNotEmpty() && key != "COUNT" && key != "UNTIL"
        }
        return (parts + "UNTIL=${formatRruleUtc(untilMillis, isAllDay)}").joinToString(";")
    }

    /** Formats [millis] as an RRULE UTC value (date-only when [dateOnly]). */
    private fun formatRruleUtc(millis: Long, dateOnly: Boolean): String {
        val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        cal.timeInMillis = millis
        val date = String.format(
            java.util.Locale.US,
            "%04d%02d%02d",
            cal.get(java.util.Calendar.YEAR),
            cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH)
        )
        if (dateOnly) return date
        return date + String.format(
            java.util.Locale.US,
            "T%02d%02d%02dZ",
            cal.get(java.util.Calendar.HOUR_OF_DAY),
            cal.get(java.util.Calendar.MINUTE),
            cal.get(java.util.Calendar.SECOND)
        )
    }

    /**
     * Reads ACCOUNT_NAME and ACCOUNT_TYPE for a calendar. Needed to build
     * sync-adapter URIs for event updates.
     */
    private fun readCalendarAccount(calendarId: String): Pair<String, String>? {
        val projection = arrayOf(
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE
        )
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            "${CalendarContract.Calendars._ID} = ?",
            arrayOf(calendarId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val nameIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
            val typeIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_TYPE)
            return Pair(cursor.getString(nameIdx), cursor.getString(typeIdx))
        }
        return null
    }

    /**
     * Updates an event row with sync-adapter context (CALLER_IS_SYNCADAPTER +
     * ACCOUNT_NAME + ACCOUNT_TYPE query params on the URI). Required when
     * the values touch protected columns like RRULE — without sync-adapter
     * context, AOSP's CalendarProvider2 silently strips those columns from
     * non-sync-adapter updates, reporting rows-matched as if the update
     * succeeded while leaving the actual stored values unchanged. Symptom:
     * the next Instances query returns the old expansion as if the RRULE
     * change never happened.
     *
     * Falls back to a non-sync-adapter update if the calendar's account
     * can't be read, which should only happen if the calendar was deleted
     * between the row read and the update.
     */
    private fun updateEventAsSyncAdapter(
        eventId: String,
        calendarId: String,
        values: android.content.ContentValues
    ): Int {
        val account = readCalendarAccount(calendarId)
        val uri = if (account != null) {
            CalendarContract.Events.CONTENT_URI.buildUpon()
                .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                .appendQueryParameter(CalendarContract.Events.ACCOUNT_NAME, account.first)
                .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, account.second)
                .build()
        } else {
            CalendarContract.Events.CONTENT_URI
        }
        return context.contentResolver.update(
            uri,
            values,
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId)
        )
    }

    /**
     * Builds a delete URI with sync-adapter context for the given event.
     * Without CALLER_IS_SYNCADAPTER, the Calendar Provider on real devices
     * only marks the row as DELETED=1 (for sync propagation) instead of
     * physically removing it. Falls back to the plain URI if the calendar
     * account can't be read.
     */
    private fun buildDeleteUri(eventId: String): android.net.Uri {
        // Look up the event's calendar ID so we can get the account.
        val calendarId = context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events.CALENDAR_ID),
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(cursor.getColumnIndexOrThrow(CalendarContract.Events.CALENDAR_ID))
            } else null
        } ?: return CalendarContract.Events.CONTENT_URI

        val account = readCalendarAccount(calendarId)
            ?: return CalendarContract.Events.CONTENT_URI

        return CalendarContract.Events.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_NAME, account.first)
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, account.second)
            .build()
    }
}
