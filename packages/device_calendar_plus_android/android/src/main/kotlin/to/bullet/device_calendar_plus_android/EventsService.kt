package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import java.util.Date

private const val MINUTES_PER_DAY = 1440

/**
 * Selects an event row by `_ID`, skipping DELETED=1 tombstones. A tombstone
 * is what a non-sync-adapter delete leaves on an event with a `_sync_id` — a
 * synced calendar's, or a local series the plugin has keyed (see
 * [EventsService.ensureLocalSeriesSyncId]). Instances queries already skip
 * it, so [EventsService.getEvent] and [EventsService.readEventRow] read it as
 * gone too: otherwise an edit or a per-occurrence delete would write against
 * a row that never shows in a listing.
 */
private val liveEventById =
    "${CalendarContract.Events._ID} = ? AND ${CalendarContract.Events.DELETED} = 0"

// Default-calendar resolution reuses CalendarService rather than duplicating
// its cursor logic, so it's injected by the plugin.
class EventsService(
    private val context: Context,
    private val calendarService: CalendarService,
) {

    fun retrieveEvents(
        startDate: Date,
        endDate: Date,
        calendarIds: List<String>?
    ): Result<List<Map<String, Any>>> {
        readAccessFailure(context)?.let { return Result.failure(it) }

        val events = mutableListOf<Map<String, Any>>()

        val startMillis = startDate.time
        val endMillis = endDate.time

        // All-day events are stored at UTC midnight boundaries, but the caller
        // passes local-midnight millis. We widen the Instances query to cover
        // UTC midnight boundaries too, then post-filter by date. (issue #20)
        val queryStartUtcMidnight = localDateToUtcMidnight(startMillis)
        val queryEndUtcMidnight = localDateToUtcMidnight(endMillis)

        val effectiveStart = minOf(startMillis, queryStartUtcMidnight)
        val effectiveEnd = maxOf(endMillis, queryEndUtcMidnight)

        val uri = instancesUri(effectiveStart, effectiveEnd)

        val columns = EventColumns.instances

        val selections = mutableListOf<String>()
        val args = mutableListOf<String>()

        if (calendarIds != null && calendarIds.isNotEmpty()) {
            val placeholders = calendarIds.joinToString(",") { "?" }
            selections.add("${CalendarContract.Instances.CALENDAR_ID} IN ($placeholders)")
            args.addAll(calendarIds)
        }

        val selection = if (selections.isNotEmpty()) selections.joinToString(" AND ") else null
        val selectionArgs = if (args.isNotEmpty()) args.toTypedArray() else null

        try {
            context.contentResolver.query(
                uri,
                columns.projection,
                selection,
                selectionArgs,
                "${columns.start} ASC"
            )?.use { cursor ->
                val beginIdx = cursor.getColumnIndexOrThrow(columns.start)
                val endIdx = cursor.getColumnIndexOrThrow(columns.end)
                val allDayIdx = cursor.getColumnIndexOrThrow(columns.allDay)

                while (cursor.moveToNext()) {
                    val eventBeginMillis = cursor.getLong(beginIdx)
                    val eventEndMillis = cursor.getLong(endIdx)
                    val isAllDay = cursor.getInt(allDayIdx) == 1

                    if (!isInRange(isAllDay, eventBeginMillis, eventEndMillis,
                            startMillis, endMillis, queryStartUtcMidnight, queryEndUtcMidnight)) {
                        continue
                    }

                    events.add(buildEventMapFromCursor(cursor, columns))
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

        // Sort on the map's startDate, not the cursor's BEGIN: the cursor is
        // in BEGIN order, but buildEventMapFromCursor rewrites all-day starts
        // from UTC midnight to local midnight, so the two orders diverge once
        // all-day and timed events mix in a non-UTC zone (#122). Mirrors iOS.
        // sortBy is stable, so BEGIN order still breaks ties. startDate is
        // always present in the map, so the cast is a hard invariant, not a
        // fallback.
        events.sortBy { it["startDate"] as Long }

        return Result.success(events)
    }
    
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
    
    // Projection/read contract (why getColumnIndexOrThrow): see the
    // EventColumns KDoc.
    private fun buildEventMapFromCursor(
        cursor: android.database.Cursor,
        columns: EventColumns
    ): Map<String, Any> {
        val eventIdIndex = cursor.getColumnIndexOrThrow(columns.eventId)
        val calendarIdIndex = cursor.getColumnIndexOrThrow(columns.calendarId)
        val titleIndex = cursor.getColumnIndexOrThrow(columns.title)
        val descriptionIndex = cursor.getColumnIndexOrThrow(columns.description)
        val locationIndex = cursor.getColumnIndexOrThrow(columns.location)
        val startIndex = cursor.getColumnIndexOrThrow(columns.start)
        val endIndex = cursor.getColumnIndexOrThrow(columns.end)
        val durationIndex = cursor.getColumnIndexOrThrow(columns.duration)
        val allDayIndex = cursor.getColumnIndexOrThrow(columns.allDay)
        val availabilityIndex = cursor.getColumnIndexOrThrow(columns.availability)
        val statusIndex = cursor.getColumnIndexOrThrow(columns.status)
        val timeZoneIndex = cursor.getColumnIndexOrThrow(columns.timeZone)
        val recurrenceRuleIndex = cursor.getColumnIndexOrThrow(columns.recurrenceRule)
        val urlIndex = cursor.getColumnIndexOrThrow(columns.url)
        val eventColorIndex = cursor.getColumnIndexOrThrow(columns.eventColor)

        val eventId = cursor.getString(eventIdIndex)
        val calendarId = cursor.getString(calendarIdIndex)
        val title = if (!cursor.isNull(titleIndex)) cursor.getString(titleIndex) else ""
        val description = if (!cursor.isNull(descriptionIndex)) cursor.getString(descriptionIndex) else null
        val location = if (!cursor.isNull(locationIndex)) cursor.getString(locationIndex) else null
        val rawStart = cursor.getLong(startIndex)
        // A recurring master stores DURATION, not DTEND (#122). With neither
        // usable, a read reports what is stored (a zero-length event); the
        // write side's one-hour default in eventDurationMillis is a choice made
        // only when a length must be produced.
        val rawEnd = storedEndMillis(
            rawStart,
            if (!cursor.isNull(endIndex)) cursor.getLong(endIndex) else null,
            if (!cursor.isNull(durationIndex)) cursor.getString(durationIndex) else null
        ) ?: rawStart
        val allDay = if (!cursor.isNull(allDayIndex)) cursor.getInt(allDayIndex) == 1 else false
        val availability = if (!cursor.isNull(availabilityIndex)) cursor.getInt(availabilityIndex) else null
        val status = if (!cursor.isNull(statusIndex)) cursor.getInt(statusIndex) else null
        val timeZone = if (!cursor.isNull(timeZoneIndex)) cursor.getString(timeZoneIndex) else null
        val recurrenceRule = if (!cursor.isNull(recurrenceRuleIndex)) cursor.getString(recurrenceRuleIndex) else null
        val url = if (!cursor.isNull(urlIndex)) cursor.getString(urlIndex) else null
        val eventColor = if (!cursor.isNull(eventColorIndex)) cursor.getInt(eventColorIndex) else null
        
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
        
        // Add URL if available (Android: CUSTOM_APP_URI)
        if (url != null) {
            eventMap["url"] = url
        }

        // Custom per-event color (EVENT_COLOR), read-only. Null when the event
        // uses the calendar's color.
        if (eventColor != null) {
            eventMap["colorHex"] = ColorHelper.colorToHex(eventColor)
        }

        // Query attendees
        val attendees = queryAttendees(eventId.toLong())
        if (attendees.isNotEmpty()) {
            eventMap["attendees"] = attendees
        }

        // Query relative reminders (minutes before start)
        val reminders = queryReminderMinutes(eventId.toLong())
        if (reminders.isNotEmpty()) {
            eventMap["reminders"] = reminders
        }

        return eventMap
    }

    /**
     * Reads the relative reminders of an event as whole minutes before start.
     *
     * Keeps only alert/default-method rows (the ones the plugin writes); email
     * and SMS reminders are out of scope and skipped. A row with MINUTES_DEFAULT
     * (-1) carries no fixed offset, so it is skipped too. Returns an empty list
     * when the event has no qualifying reminders.
     */
    private fun queryReminderMinutes(eventId: Long): List<Int> {
        val minutes = mutableListOf<Int>()
        try {
            context.contentResolver.query(
                CalendarContract.Reminders.CONTENT_URI,
                arrayOf(
                    CalendarContract.Reminders.MINUTES,
                    CalendarContract.Reminders.METHOD,
                ),
                "${CalendarContract.Reminders.EVENT_ID} = ?",
                arrayOf(eventId.toString()),
                null
            )?.use { cursor ->
                val minutesIdx = cursor.getColumnIndexOrThrow(CalendarContract.Reminders.MINUTES)
                val methodIdx = cursor.getColumnIndexOrThrow(CalendarContract.Reminders.METHOD)
                while (cursor.moveToNext()) {
                    val method = if (cursor.isNull(methodIdx)) {
                        CalendarContract.Reminders.METHOD_DEFAULT
                    } else {
                        cursor.getInt(methodIdx)
                    }
                    if (method != CalendarContract.Reminders.METHOD_ALERT &&
                        method != CalendarContract.Reminders.METHOD_DEFAULT) {
                        continue
                    }
                    if (cursor.isNull(minutesIdx)) continue
                    val value = cursor.getInt(minutesIdx)
                    // MINUTES_DEFAULT (-1) means "use the calendar's default" —
                    // it has no concrete offset to report.
                    if (value < 0) continue
                    minutes.add(value)
                }
            }
        } catch (_: Exception) {
            // Silently return what we have if the reminder query fails.
        }
        return minutes
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
    
    /**
     * Reads one event: the master row for a bare [eventId], or the occurrence
     * that starts at [timestamp] when one is given. Null when nothing matches.
     */
    fun getEvent(eventId: String, timestamp: Long?): Result<Map<String, Any>?> {
        readAccessFailure(context)?.let { return Result.failure(it) }

        if (timestamp == null) {
            return querySingleEvent(
                CalendarContract.Events.CONTENT_URI,
                EventColumns.events,
                liveEventById,
                arrayOf(eventId)
            )
        }

        // An instance ID carries the occurrence's raw BEGIN (see
        // buildEventMapFromCursor), so the Instances row is an exact match on
        // EVENT_ID and BEGIN. The window only exists because the Instances URI
        // needs one; its width is arbitrary, provided it overlaps the row.
        val uri = instancesUri(timestamp - 1000, timestamp + 1000)
        return querySingleEvent(
            uri,
            EventColumns.instances,
            "${CalendarContract.Instances.EVENT_ID} = ? AND ${CalendarContract.Instances.BEGIN} = ?",
            arrayOf(eventId, timestamp.toString())
        )
    }

    /** The first row of [uri] matching [selection] as an event map, or null. */
    private fun querySingleEvent(
        uri: android.net.Uri,
        columns: EventColumns,
        selection: String,
        selectionArgs: Array<String>
    ): Result<Map<String, Any>?> {
        try {
            val event = context.contentResolver.query(
                uri,
                columns.projection,
                selection,
                selectionArgs,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) buildEventMapFromCursor(cursor, columns) else null
            }
            return Result.success(event)
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
            // No permission gate: ACTION_INSERT hands the event to the calendar
            // app, which saves it with its own access — the docs are explicit
            // that the caller needs neither READ_ nor WRITE_CALENDAR.
            val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)

            if (title != null) intent.putExtra(CalendarContract.Events.TITLE, title)
            if (description != null) intent.putExtra(CalendarContract.Events.DESCRIPTION, description)
            if (location != null) intent.putExtra(CalendarContract.Events.EVENT_LOCATION, location)
            if (startDate != null) intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startDate)
            if (endDate != null) intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endDate)
            // EXTRA_EVENT_ALL_DAY is a *boolean* extra — calendar apps read it
            // with getBooleanExtra, which ignores an Integer value entirely.
            if (isAllDay != null) intent.putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, isAllDay)
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
        } catch (e: Exception) {
            // No SecurityException special-case: ACTION_INSERT needs no calendar
            // permission, so one here isn't a calendar-permission problem and
            // mapping it to PERMISSION_DENIED would send callers down a
            // requestPermissions loop that can't help.
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
        recurrenceRule: String?,
        reminders: List<Int>?
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

                // Flag the event as having alarms so the provider expands them.
                val hasReminders = reminders != null && reminders.isNotEmpty()
                put(CalendarContract.Events.HAS_ALARM, if (hasReminders) 1 else 0)
            }

            val uri = context.contentResolver.insert(
                CalendarContract.Events.CONTENT_URI,
                values
            )

            if (uri != null) {
                val eventId = uri.lastPathSegment
                if (eventId != null) {
                    // Reminders attach as separate rows keyed by EVENT_ID — this
                    // is the same whether or not the event recurs, so the
                    // RRULE/DURATION handling above is untouched.
                    if (reminders != null && reminders.isNotEmpty()) {
                        insertReminderRows(eventId.toLong(), reminders)
                    }
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
        fullAccessFailure(context)?.let { return Result.failure(it) }

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
     * the whole series when recurring — and any detached occurrences keyed
     * to it by `original_id`.
     *
     * The exceptions have to be named here because the provider cascades a
     * series delete only to a master with no `_sync_id`, and both a synced
     * calendar's master and a local one edited per occurrence (see
     * [ensureLocalSeriesSyncId]) carry one. One selection-based delete covers
     * master and exceptions together: the provider runs it as a single
     * transaction over every matching row, so there is no window where the
     * master is gone but its exceptions are not. A consequence worth keeping:
     * exceptions orphaned by a master that is already gone still match, so
     * deleting that ID cleans them up and reports success, not NOT_FOUND.
     */
    private fun deleteEventMaster(eventId: String): Result<Unit> {
        // Sync-adapter context so the Calendar Provider physically removes
        // the rows instead of just setting DELETED=1. Without it, the event
        // survives deletion on real devices (where a sync adapter is present)
        // and getEvent still returns it.
        val deletedRows = context.contentResolver.delete(
            buildDeleteUri(eventId),
            "${CalendarContract.Events._ID} = ? OR ${CalendarContract.Events.ORIGINAL_ID} = ?",
            arrayOf(eventId, eventId)
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
        fullAccessFailure(context)?.let { return Result.failure(it) }

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
        val row = readEventRow(eventId).getOrElse { return Result.failure(it) }

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

        // A reminders set/clear also flips HAS_ALARM so the provider expands
        // (or drops) the alarms. Unchanged leaves the column alone.
        applyRemindersHasAlarm(values, patch.reminders)

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

        // Reminder rows live in a separate table keyed by EVENT_ID — rewrite
        // them after the event row update (no-op when unchanged).
        applyRemindersRows(eventId.toLong(), patch.reminders)

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
        val series = readRecurringRow(eventId).getOrElse { return Result.failure(it) }

        val effectiveIsAllDay = patch.isAllDay ?: series.row.allDay
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
            timestamp + eventDurationMillis(series.row)
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
        // The exception is a fresh event row, so a reminders set/clear sets its
        // HAS_ALARM. Unchanged inherits the parent's value implicitly.
        applyRemindersHasAlarm(values, patch.reminders)

        val exceptionId = insertException(series, values, asSyncAdapter = false)
            .getOrElse { return Result.failure(it) }
        // Reminder rows attach to the detached exception's own event id.
        applyRemindersRows(exceptionId.toLong(), patch.reminders)
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
        fullAccessFailure(context)?.let { return Result.failure(it) }

        return try {
            if (span != "allEvents" && span != "thisAndFollowing") {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "Unknown update span: $span"
                    )
                )
            }

            val row = readEventRow(eventId).getOrElse { return Result.failure(it) }

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
                    row, timestamp, newStartMillis,
                    durationMinutes, recurrenceRule, patch
                )
                else -> updateRecurringAllEvents(
                    row, timestamp, newStartMillis,
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
        // The anchor shifts relative to the occurrence the caller pointed at
        // (timestamp), or the series anchor itself when none was given — and
        // then onto the new rule, when one is given (#140).
        val (newStart, newDurationMs) = resolveSeriesTimes(
            row.dtstart, timestamp ?: row.dtstart, eventDurationMillis(row),
            newStartMillis, durationMinutes, recurrenceRule, row.timeZone,
            effectiveIsAllDay
        ).getOrElse { return Result.failure(it) }
        // A `start` equal to the current anchor is still a rewrite: the
        // DTSTART/DURATION (and RRULE, below) re-put is what makes the
        // provider re-expand the series.
        val rewriteTimeColumns = newStartMillis != null || durationMinutes != null ||
            newStart != row.dtstart
        if (rewriteTimeColumns || wasRecurring != willBeRecurring) {
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

        applyRemindersHasAlarm(values, patch.reminders)

        // RRULE writes require sync-adapter context on Android — see
        // updateEventAsSyncAdapter for the rationale.
        val updatedRows = updateEventAsSyncAdapter(row, values)
        if (updatedRows == 0) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID ${row.id} not found"
                )
            )
        }

        // Reminder rows attach to the (master) event row by EVENT_ID — the same
        // for recurring and non-recurring, so no DURATION/RRULE interaction.
        applyRemindersRows(row.id.toLong(), patch.reminders)
        return Result.success(row.id)
    }

    private fun updateRecurringThisAndFollowing(
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

        val (_, rrule) = row.asSeries().getOrElse { return Result.failure(it) }

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
                val originalCount = RruleString.count(rrule)
                if (originalCount != null) {
                    val before = countInstancesBefore(row.id, timestamp)
                    RruleString.withCount(rrule, maxOf(1, originalCount - before))
                } else {
                    rrule
                }
            }
        }

        // The new series is anchored at the split occurrence, shifted to the
        // caller's new start (the reference and base are both the occurrence)
        // and then onto the new rule, which may not generate the occurrence's
        // day (a Saturday series switched to Sundays) — without that the
        // provider keeps the old day as an extra first occurrence (#140).
        // Duration is the master's unless overridden.
        val (newStart, newDurationMs) = resolveSeriesTimes(
            timestamp, timestamp, eventDurationMillis(row),
            newStartMillis, durationMinutes, recurrenceRule, row.timeZone,
            effectiveIsAllDay
        ).getOrElse { return Result.failure(it) }
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

        // The new series carries the patch's reminders when set/cleared, else
        // it inherits the original series' reminders.
        val effectiveReminders = when (val r = patch.reminders) {
            is EventFieldPatch.RemindersPatch.Set -> r.minutes
            is EventFieldPatch.RemindersPatch.Clear -> emptyList()
            EventFieldPatch.RemindersPatch.Unchanged -> queryReminderMinutes(row.id.toLong())
        }
        if (effectiveReminders.isNotEmpty()) {
            insertReminderRows(newEventId.toLong(), effectiveReminders)
            setHasAlarm(newEventId.toLong(), row.calendarId, true)
        }

        // Truncate the original series to end just before the anchor. UNTIL is
        // inclusive, so cutting it one second early keeps the anchor occurrence
        // off the old series — it belongs to the new one.
        //
        // RRULE writes go through updateEventAsSyncAdapter; we also rewrite
        // DTSTART/DURATION with their existing values to force Android's
        // CalendarProvider to invalidate the Instances cache (it doesn't
        // always when only RRULE changes — see deleteRecurringThisAndFollowing).
        val truncatedRrule = RruleString.withUntil(rrule, timestamp - 1000, row.allDay)
        val truncateValues = android.content.ContentValues().apply {
            put(CalendarContract.Events.RRULE, truncatedRrule)
            put(CalendarContract.Events.DTSTART, row.dtstart)
            if (row.duration != null) {
                put(CalendarContract.Events.DURATION, row.duration)
            }
        }
        val truncatedRows = updateEventAsSyncAdapter(row, truncateValues)
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
                    "Failed to truncate original series for event ${row.id}"
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
        fullAccessFailure(context)?.let { return Result.failure(it) }

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

        val (row, rrule) = readRecurringRow(eventId).getOrElse { return Result.failure(it) }

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
        val truncatedRrule = RruleString.withUntil(rrule, timestamp - 1000, row.allDay)
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.RRULE, truncatedRrule)
            put(CalendarContract.Events.DTSTART, row.dtstart)
            if (row.duration != null) {
                put(CalendarContract.Events.DURATION, row.duration)
            }
        }
        val updatedRows = updateEventAsSyncAdapter(row, values)
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
        val series = readRecurringRow(eventId).getOrElse { return Result.failure(it) }

        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, timestamp)
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CANCELED)
        }
        return insertException(series, values, asSyncAdapter = true).map { }
    }

    /**
     * A master [row] proven recurring: its [rrule] is the row's, non-null.
     * The type is what the series writers — [insertException] and
     * [ensureLocalSeriesSyncId] — take, so a one-off event's row cannot
     * reach them.
     */
    private data class SeriesRow(val row: EventRow, val rrule: String)

    /**
     * The master row a per-occurrence call addresses — an exception write in
     * [updateEventInstance] and [deleteEventInstance], the split in
     * [deleteRecurringThisAndFollowing]. NOT_FOUND when the event is missing
     * (or a DELETED tombstone), then [asSeries]. The split in
     * [updateRecurringThisAndFollowing] takes that second step alone, on the
     * row [updateRecurring] already read.
     */
    private fun readRecurringRow(eventId: String): Result<SeriesRow> {
        val row = readEventRow(eventId).getOrElse { return Result.failure(it) }
        return row.asSeries()
    }

    /**
     * This master row as a [SeriesRow]: INVALID_ARGUMENTS when it is not
     * recurring, since a one-off event has no occurrence apart from itself.
     */
    private fun EventRow.asSeries(): Result<SeriesRow> {
        val rrule = this.rrule
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "Event $id is not recurring, so it has no single occurrence " +
                        "to address; edit or delete the event itself instead"
                )
            )
        return Result.success(SeriesRow(this, rrule))
    }

    /**
     * Inserts an exception row carrying [values] against [series]' master:
     * the one write behind every per-occurrence edit or delete. It owns the
     * #153 keying — a local series gets its `_sync_id` here, before the
     * insert — so a future exception writer cannot skip it. Returns the new
     * exception's own event ID.
     *
     * [asSyncAdapter] is the caller's choice on purpose: the cancellation in
     * [deleteEventInstance] has always gone as a sync adapter, the edit in
     * [updateEventInstance] as a plain caller (which also marks the exception
     * DIRTY for a synced calendar's adapter to upload). Neither has been
     * tried the other way against a synced calendar, so the difference is
     * kept rather than unified blind.
     */
    private fun insertException(
        series: SeriesRow,
        values: android.content.ContentValues,
        asSyncAdapter: Boolean
    ): Result<String> {
        ensureLocalSeriesSyncId(series).getOrElse { return Result.failure(it) }

        val base = CalendarContract.Events.CONTENT_EXCEPTION_URI
        val uri = (if (asSyncAdapter) syncAdapterUri(base, series.row.account) else base)
            .buildUpon()
            .appendPath(series.row.id)
            .build()

        val exceptionId = context.contentResolver.insert(uri, values)?.lastPathSegment
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to write an exception for event ${series.row.id}"
                )
            )
        return Result.success(exceptionId)
    }

    /**
     * A live master row from the Events view. [account] is the calendar's,
     * which the view joins in: the sync-adapter URIs every write against
     * the row needs are built from it, without a second query.
     */
    private data class EventRow(
        val id: String,
        val calendarId: String,
        val account: CalendarAccount,
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
        val rrule: String?,
        val syncId: String?
    )

    /**
     * Reads the master row of an event straight from the Events table:
     * NOT_FOUND when the event is missing (or a DELETED tombstone).
     */
    private fun readEventRow(eventId: String): Result<EventRow> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CALENDAR_ID,
            CalendarContract.Events.ACCOUNT_NAME,
            CalendarContract.Events.ACCOUNT_TYPE,
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
            CalendarContract.Events.RRULE,
            CalendarContract.Events._SYNC_ID
        )
        context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            liveEventById,
            arrayOf(eventId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use
            fun str(column: String): String? {
                val index = cursor.getColumnIndexOrThrow(column)
                return if (cursor.isNull(index)) null else cursor.getString(index)
            }
            fun long(column: String): Long? {
                val index = cursor.getColumnIndexOrThrow(column)
                return if (cursor.isNull(index)) null else cursor.getLong(index)
            }
            return Result.success(EventRow(
                id = str(CalendarContract.Events._ID) ?: eventId,
                calendarId = str(CalendarContract.Events.CALENDAR_ID) ?: "",
                account = cursor.calendarAccount(),
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
                rrule = str(CalendarContract.Events.RRULE),
                syncId = str(CalendarContract.Events._SYNC_ID)
            ))
        }
        return Result.failure(
            CalendarException(
                PlatformExceptionCodes.NOT_FOUND,
                "Event with ID $eventId not found"
            )
        )
    }

    /**
     * Gives a recurring series on a local calendar a `_sync_id` before an
     * exception is written against it. The Calendar Provider keys a series'
     * exceptions by `_sync_id` / `original_sync_id`; without one, the
     * exception insert drops the master's own occurrences from the Instances
     * cache (#153).
     *
     * Only local calendars are touched: nothing else will ever assign them a
     * `_sync_id`, whereas a synced calendar's adapter owns that column. The
     * write goes as a sync adapter (the column is read-only otherwise).
     *
     * The trade: the provider physically deletes an event only for a sync
     * adapter or when `_sync_id` is empty, so once a local series carries
     * one, a delete by a non-sync-adapter caller (the stock Calendar app,
     * say) leaves it as a DELETED=1 row that no adapter will ever collect.
     * Instances queries skip such rows, [getEvent] and [readEventRow] filter
     * them out, and the plugin's own deletes go through [buildDeleteUri] as
     * a sync adapter.
     *
     * Exceptions already written against the series before it had an id — by
     * an older plugin version or another app — join the family with this one
     * write: the provider's `original_sync_update` trigger (in AOSP's
     * CalendarDatabaseHelper since database version 301, Android 4.0) copies
     * a changed `_sync_id` into the `original_sync_id` of every row whose
     * `original_id` is this master. That is an upgrade-only path: the id is
     * now assigned before the first exception write, so the public API can no
     * longer produce a keyless series with exceptions.
     *
     * Fails with OPERATION_FAILED when the provider refuses the key write —
     * matching no row, whatever the reason — so the caller never writes an
     * exception against a master that is still keyless, which is the very
     * write #153 comes from. A master that vanished between the caller's
     * read and now lands here too: the exception insert would throw on the
     * missing original anyway, and the outer catch maps that to
     * OPERATION_FAILED as well.
     */
    private fun ensureLocalSeriesSyncId(series: SeriesRow): Result<Unit> {
        val row = series.row
        if (row.syncId != null) return Result.success(Unit)
        if (!row.account.isLocal) return Result.success(Unit)

        val syncId = "device_calendar_plus:${java.util.UUID.randomUUID()}"
        val updated = context.contentResolver.update(
            syncAdapterUri(CalendarContract.Events.CONTENT_URI, row.account),
            android.content.ContentValues().apply {
                put(CalendarContract.Events._SYNC_ID, syncId)
            },
            "${CalendarContract.Events._ID} = ?",
            arrayOf(row.id)
        )
        if (updated == 0) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Could not key series ${row.id} before writing its exception"
                )
            )
        }
        return Result.success(Unit)
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

    /**
     * Inserts one [CalendarContract.Reminders] row per minute value, each a
     * relative METHOD_ALERT reminder that many minutes before the event start.
     */
    private fun insertReminderRows(eventId: Long, minutes: List<Int>) {
        for (m in minutes) {
            val values = android.content.ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, m)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, values)
        }
    }

    /** Removes all reminder rows for [eventId]. */
    private fun deleteReminderRows(eventId: Long) {
        context.contentResolver.delete(
            CalendarContract.Reminders.CONTENT_URI,
            "${CalendarContract.Reminders.EVENT_ID} = ?",
            arrayOf(eventId.toString())
        )
    }

    /**
     * Applies a reminders [patch] to the rows of [eventId]: a set replaces the
     * whole reminder set (delete then re-insert), a clear removes them all, and
     * unchanged leaves the rows untouched.
     */
    private fun applyRemindersRows(
        eventId: Long,
        patch: EventFieldPatch.RemindersPatch
    ) {
        when (patch) {
            EventFieldPatch.RemindersPatch.Unchanged -> {}
            EventFieldPatch.RemindersPatch.Clear -> deleteReminderRows(eventId)
            is EventFieldPatch.RemindersPatch.Set -> {
                deleteReminderRows(eventId)
                if (patch.minutes.isNotEmpty()) {
                    insertReminderRows(eventId, patch.minutes)
                }
            }
        }
    }

    /**
     * Writes HAS_ALARM into [values] to match a reminders [patch]: a non-empty
     * set flips it on, an empty set or clear flips it off, unchanged leaves the
     * column out so the existing flag stands.
     */
    private fun applyRemindersHasAlarm(
        values: android.content.ContentValues,
        patch: EventFieldPatch.RemindersPatch
    ) {
        when (patch) {
            EventFieldPatch.RemindersPatch.Unchanged -> {}
            EventFieldPatch.RemindersPatch.Clear ->
                values.put(CalendarContract.Events.HAS_ALARM, 0)
            is EventFieldPatch.RemindersPatch.Set ->
                values.put(
                    CalendarContract.Events.HAS_ALARM,
                    if (patch.minutes.isNotEmpty()) 1 else 0
                )
        }
    }

    /** Sets HAS_ALARM for an event row (used when reminders are added later). */
    private fun setHasAlarm(eventId: Long, calendarId: String, hasAlarm: Boolean) {
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.HAS_ALARM, if (hasAlarm) 1 else 0)
        }
        context.contentResolver.update(
            CalendarContract.Events.CONTENT_URI,
            values,
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId.toString())
        )
    }

    private fun availabilityToInt(availability: String): Int {
        return when (availability) {
            "free" -> CalendarContract.Events.AVAILABILITY_FREE
            "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
            else -> CalendarContract.Events.AVAILABILITY_BUSY
        }
    }

    /**
     * Resolves the start and duration for a series-level edit; iOS's
     * counterpart is `resolveSeriesStart`.
     *
     * When [newStartMillis] is given the start is shifted by the wall-clock
     * delta from [referenceMillis] to [newStartMillis] (see [shiftDate]). A
     * new [rrule] then moves it onto the first day the rule generates, keeping
     * its wall-clock time — the anchor a series switched to a new rule must
     * have, or the provider emits the old day as an extra occurrence (#140).
     * A rule that generates nothing within five years of the anchor fails
     * with INVALID_ARGUMENTS rather than leaving that orphan behind. The
     * duration is overridden when [durationMinutes] is given.
     */
    private fun resolveSeriesTimes(
        baseMillis: Long,
        referenceMillis: Long,
        existingDurationMillis: Long,
        newStartMillis: Long?,
        durationMinutes: Int?,
        rrule: String?,
        timeZoneId: String?,
        isAllDay: Boolean
    ): Result<Pair<Long, Long>> {
        val tz = seriesTimeZone(timeZoneId, isAllDay)
        val shiftedStart = if (newStartMillis != null) {
            shiftDate(baseMillis, referenceMillis, newStartMillis, tz, isAllDay)
        } else {
            baseMillis
        }
        val newStart = if (rrule != null) {
            RecurrenceAnchor.firstMatch(rrule, shiftedStart, tz)
                ?: return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "recurrenceRule generates no occurrences within five years of the anchor"
                    )
                )
        } else {
            shiftedStart
        }
        val newDurationMs = if (durationMinutes != null) {
            durationMinutes.toLong() * 60_000L
        } else {
            existingDurationMillis
        }
        return Result.success(Pair(newStart, newDurationMs))
    }

    /**
     * The timezone that frames a series' calendar days: the event's own
     * (device default when [timeZoneId] is null), except that all-day events
     * are stored as UTC midnight and so live in UTC.
     */
    private fun seriesTimeZone(timeZoneId: String?, isAllDay: Boolean): java.util.TimeZone =
        when {
            isAllDay -> java.util.TimeZone.getTimeZone("UTC")
            timeZoneId != null -> java.util.TimeZone.getTimeZone(timeZoneId)
            else -> java.util.TimeZone.getDefault()
        }

    /**
     * Translates [baseMillis] by the wall-clock delta from [referenceMillis]
     * to [newStartMillis]: shifts by the whole-day difference and sets the
     * time-of-day to [newStartMillis]'s. DST-safe — it counts calendar days
     * and sets a wall-clock time rather than adding a raw interval.
     *
     * Dates are interpreted in [tz], the series' timezone (see
     * [seriesTimeZone]). All-day events are stored as UTC midnight, so they
     * shift in UTC by whole days with the time-of-day left at midnight. The
     * anchor-shift that lets [updateRecurring] move both the time and the day
     * of a series (issue #103); iOS's counterpart is `shiftStart`.
     */
    private fun shiftDate(
        baseMillis: Long,
        referenceMillis: Long,
        newStartMillis: Long,
        tz: java.util.TimeZone,
        isAllDay: Boolean
    ): Long {
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
        val parts = RruleString.params(rrule)
        val hasByDay = "BYDAY" in parts
        val hasByMonthDay = "BYMONTHDAY" in parts
        val hasByMonth = "BYMONTH" in parts
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

    /** Resolves an event's duration, falling back to one hour when unknown. */
    private fun eventDurationMillis(row: EventRow): Long =
        storedEndMillis(row.dtstart, row.dtend, row.duration)?.let { it - row.dtstart } ?: 3_600_000L

    /** Number of occurrences of [eventId] that start before [beforeMillis]. */
    private fun countInstancesBefore(eventId: String, beforeMillis: Long): Int {
        // Five-year look-back window: covers daily/weekly/monthly easily, and
        // yearly rules with an interval of up to five.
        val windowStart = beforeMillis - 5L * 366 * 24 * 3600 * 1000
        val uri = instancesUri(windowStart, beforeMillis)
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
     * The account a calendar belongs to. [isLocal] means no sync adapter
     * will ever touch its rows, so columns the provider reserves for one
     * (`_sync_id`, say) are the plugin's to manage.
     */
    private data class CalendarAccount(val name: String, val type: String) {
        val isLocal: Boolean get() = type == CalendarContract.ACCOUNT_TYPE_LOCAL
    }

    /**
     * The [CalendarAccount] of the Events row under the cursor, from its
     * ACCOUNT_NAME and ACCOUNT_TYPE columns. The provider guarantees both
     * on every calendar, so a NULL is a broken invariant and throws rather
     * than standing in a made-up value — the one policy for the account
     * columns, wherever they are read off a row. ([readEventRow]'s other
     * non-null columns keep their older fallbacks.)
     */
    private fun android.database.Cursor.calendarAccount(): CalendarAccount {
        fun str(column: String): String =
            checkNotNull(getString(getColumnIndexOrThrow(column))) {
                "Events row has no $column"
            }
        return CalendarAccount(
            name = str(CalendarContract.Events.ACCOUNT_NAME),
            type = str(CalendarContract.Events.ACCOUNT_TYPE)
        )
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
     */
    private fun updateEventAsSyncAdapter(
        row: EventRow,
        values: android.content.ContentValues
    ): Int =
        context.contentResolver.update(
            syncAdapterUri(CalendarContract.Events.CONTENT_URI, row.account),
            values,
            "${CalendarContract.Events._ID} = ?",
            arrayOf(row.id)
        )

    /** [base] (an Events or exception URI) with sync-adapter context for [account]. */
    private fun syncAdapterUri(
        base: android.net.Uri,
        account: CalendarAccount
    ): android.net.Uri =
        base.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_NAME, account.name)
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, account.type)
            .build()

    /**
     * Builds a delete URI with sync-adapter context for the given event.
     * Without CALLER_IS_SYNCADAPTER, the Calendar Provider on real devices
     * only marks the row as DELETED=1 (for sync propagation) instead of
     * physically removing it. Reads the event's account through a DELETED
     * tombstone on purpose — collecting one is the point — and falls back
     * to the plain URI when the row is gone altogether.
     */
    private fun buildDeleteUri(eventId: String): android.net.Uri {
        val account = context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(
                CalendarContract.Events.ACCOUNT_NAME,
                CalendarContract.Events.ACCOUNT_TYPE
            ),
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            cursor.calendarAccount()
        } ?: return CalendarContract.Events.CONTENT_URI

        return syncAdapterUri(CalendarContract.Events.CONTENT_URI, account)
    }
}
