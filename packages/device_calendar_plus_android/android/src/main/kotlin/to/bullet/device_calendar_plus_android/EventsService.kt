package to.bullet.device_calendar_plus_android

import android.content.Context
import android.provider.CalendarContract
import java.util.Date

private const val MINUTES_PER_DAY = 1440

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

// Default-calendar resolution reuses CalendarService rather than duplicating
// its cursor logic, so it's injected by the plugin.
class EventsService(
    private val context: Context,
    private val calendarService: CalendarService,
) {

    /** The series-row reads and writes every series edit goes through. */
    private val store = SeriesRowStore(context)

    /** The second half of a thisAndFollowing update split (#158). */
    private val detachedOccurrenceCarry = DetachedOccurrenceCarry(store)

    fun retrieveEvents(
        startDate: Date,
        endDate: Date,
        calendarIds: List<String>?
    ): Result<List<Map<String, Any>>> {
        readAccessFailure(context)?.let { return Result.failure(it) }

        val events = mutableListOf<Map<String, Any>>()

        val startMillis = startDate.time
        val endMillis = endDate.time

        // Widen to the all-day UTC-midnight edges; see
        // AllDayDates.windowEndUtcMidnight. (issue #20)
        val queryStartUtcMidnight = AllDayDates.localDateToUtcMidnight(startMillis)
        val queryEndUtcMidnight = AllDayDates.windowEndUtcMidnight(endMillis)

        val effectiveStart = minOf(startMillis, queryStartUtcMidnight)
        val effectiveEnd = maxOf(endMillis, queryEndUtcMidnight)

        val uri = EventColumns.instancesUri(effectiveStart, effectiveEnd)

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
            val effectiveEnd = if (eventEnd <= eventBegin) eventBegin + AllDayDates.MILLIS_PER_DAY else eventEnd
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
            start = AllDayDates.utcToLocalMidnight(rawStart)
            end = AllDayDates.utcToLocalMidnight(rawEnd)
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
        val uri = EventColumns.instancesUri(timestamp - 1000, timestamp + 1000)
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
     * The row ID [EventModalIntents.showEvent] opens for [eventId] (or, with
     * [timestamp], the occurrence). Looked up first because firing the intent
     * blind would open the calendar app on nothing and report success (#123):
     * a missing event fails NOT_FOUND, as on iOS. [getEvent] gates on
     * permission, so a denied caller hears that before anything about the ID.
     * Provider IPC — call it off the main thread.
     */
    fun findEventForModal(eventId: String, timestamp: Long?): Result<Long> {
        val found = getEvent(eventId, timestamp).getOrElse { return Result.failure(it) }
        // getEvent matches on the numeric row ID, so a found event always has
        // one; the rowId check is defensive, and only there to unwrap it.
        val rowId = eventId.toLongOrNull()
        if (found == null || rowId == null) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event not found with event ID: $eventId"
                )
            )
        }
        return Result.success(rowId)
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

        // Refuse a rule iOS can't store before writing anything, rather than
        // handing it to the provider: that would keep FREQ=HOURLY as an hourly
        // series, and fail malformed input only as a generic insert error.
        unsupportedRuleFailure(recurrenceRule)?.let { return Result.failure(it) }

        try {
            val startMillis = storageMillis(startDate.time, isAllDay)
            val endMillis = storageMillis(endDate.time, isAllDay)

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
     * Deletes one thing. With a [timestamp], removes only the occurrence at
     * that instant from its recurring series, as a cancelled exception;
     * without one, deletes a one-off event. A bare ID of a recurring series
     * is refused with INVALID_ARGUMENTS and nothing is deleted — whole-series
     * deletes go through [deleteRecurring] (#175).
     */
    fun deleteEvent(eventId: String, timestamp: Long? = null): Result<Unit> {
        fullAccessFailure(context)?.let { return Result.failure(it) }

        return try {
            if (timestamp != null) {
                deleteEventInstance(eventId, timestamp)
            } else {
                deleteOneOff(eventId)
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
     * The bare-event-ID path of [deleteEvent]: deletes a one-off event.
     * NOT_FOUND when the event is missing or a DELETED tombstone, and a
     * recurring series is refused before any delete — both checked against
     * the live row, as [updateOneOff] does.
     */
    private fun deleteOneOff(eventId: String): Result<Unit> {
        val row = store.readEventRow(eventId).getOrElse { return Result.failure(it) }
            .asOneOff(OneThingOperation.DELETE).getOrElse { return Result.failure(it) }
        return deleteEventWithExceptions(eventId, row.account)
    }

    /**
     * Deletes event row [eventId] and any detached occurrences keyed to it by
     * `original_id`, through [account]'s delete URI (null when the row is gone
     * altogether) — the shared primitive behind [deleteOneOff] and
     * [deleteRecurring]'s `allEvents` span, where it removes the whole series.
     *
     * The exceptions have to be named here because the provider cascades a
     * series delete only to a master with no `_sync_id`, and both a synced
     * calendar's master and a local one edited per occurrence (see
     * [SeriesRowStore.ensureLocalSeriesSyncId]) carry one. One
     * selection-based delete covers master and exceptions together: the provider runs it as a single
     * transaction over every matching row, so there is no window where the
     * master is gone but its exceptions are not. A consequence worth keeping:
     * exceptions orphaned by a master that is already gone still match, so
     * deleting that ID cleans them up and reports success, not NOT_FOUND.
     *
     * The null account, the local-tombstone case and the orphaned-exception
     * case arise only from [deleteRecurring]'s `allEvents` span:
     * [deleteOneOff] reaches this only with a live one-off row.
     */
    private fun deleteEventWithExceptions(
        eventId: String,
        account: CalendarAccount?
    ): Result<Unit> {
        // On a synced calendar this tombstones the rows (DELETED=1) for the
        // adapter to upload; on a local one it removes them — see
        // SeriesRowStore.deleteUri.
        // Either way the plugin's own reads no longer see them. A synced
        // tombstone is left out of the selection: it is already deleted as
        // far as the caller can tell, so a repeat delete reports NOT_FOUND,
        // as on iOS and on a local calendar. A local tombstone stays in,
        // since no adapter will collect it and removing it is the point.
        var selection = "(${CalendarContract.Events._ID} = ? OR " +
            "${CalendarContract.Events.ORIGINAL_ID} = ?)"
        if (account != null && !account.isLocal) {
            selection += " AND ${CalendarContract.Events.DELETED} = 0"
        }
        val deletedRows = context.contentResolver.delete(
            account?.let(store::deleteUri) ?: CalendarContract.Events.CONTENT_URI,
            selection,
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
     * Updates one thing. With a [timestamp], detaches the occurrence at that
     * instant from its recurring series and applies the changes to it alone;
     * without one, updates a one-off event. A bare ID of a recurring series
     * is refused with INVALID_ARGUMENTS and nothing is written — series edits
     * go through [updateRecurring] (#175).
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
                updateOneOff(eventId, startDate, endDate, patch)
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
     * The bare-event-ID path of [updateEvent]: updates a one-off event's row.
     * A recurring series is refused before any write.
     */
    private fun updateOneOff(
        eventId: String,
        startDate: java.util.Date?,
        endDate: java.util.Date?,
        patch: EventFieldPatch
    ): Result<Unit> {
        // The existing row decides all-day date normalization when the call
        // doesn't change the flag.
        val row = store.readEventRow(eventId).getOrElse { return Result.failure(it) }
            .asOneOff(OneThingOperation.UPDATE).getOrElse { return Result.failure(it) }

        // Build ContentValues with only provided fields
        val values = android.content.ContentValues()
        applyEventFieldValues(values, patch)

        // Update dates if provided
        // If event is/becomes all-day, need to normalize to UTC midnight
        val effectiveIsAllDay = patch.isAllDay ?: row.allDay
        if (startDate != null || endDate != null) {
            val startMillis = startDate?.let { storageMillis(it.time, effectiveIsAllDay) }
            val endMillis = endDate?.let { storageMillis(it.time, effectiveIsAllDay) }

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

        val updatedRows = store.updateEventRow(eventId, values)

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
        val series = store.readRecurringRow(eventId).getOrElse { return Result.failure(it) }

        val effectiveIsAllDay = patch.isAllDay ?: series.row.allDay
        val newStart = if (startDate != null) {
            storageMillis(startDate.time, effectiveIsAllDay)
        } else {
            timestamp
        }
        // Without an explicit endDate the occurrence's own end stays put —
        // matching iOS, where setting startDate leaves endDate untouched.
        val newEnd = if (endDate != null) {
            storageMillis(endDate.time, effectiveIsAllDay)
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

        val exceptionId = insertException(series, values)
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

            val row = store.readEventRow(eventId).getOrElse { return Result.failure(it) }

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

            // Refuse a rule iOS can't store before any write, at the point
            // iOS's updateRecurring parses it, rather than handing it to the
            // provider: that would keep FREQ=HOURLY as an hourly series.
            unsupportedRuleFailure(recurrenceRule)?.let { return Result.failure(it) }

            // A toggle to all-day moves the series into the all-day frame
            // even without a `start` or `duration`: they default to the named
            // occurrence's own start and the whole days it covers, as
            // EventKit makes of it. Without that, the timed DTSTART and
            // DURATION stayed under ALL_DAY=1 and the series read back on
            // the wrong date, or collapsed (#124).
            val togglesToAllDay = patch.isAllDay == true && !row.allDay
            val reference = timestamp ?: row.dtstart
            val startMillis = newStartMillis ?: reference.takeIf { togglesToAllDay }
            val effectiveDurationMinutes = durationMinutes
                ?: if (togglesToAllDay) {
                    allDayToggleDurationMinutes(reference, eventDurationMillis(row))
                } else {
                    null
                }

            // Bring the caller's local `start` into the stored frame (#144).
            // resolveSeriesTimes then refuses a start the kept rule doesn't
            // generate (#189; see updateRecurring docs).
            val targetStart = resolveTargetStart(startMillis, effectiveIsAllDay)
            val ruleEdit = SeriesRuleEdit.of(
                recurrenceRule,
                cleared = "recurrenceRule" in patch.clearedFields,
                existing = row.rrule
            )

            when (span) {
                "thisAndFollowing" -> updateRecurringThisAndFollowing(
                    row, timestamp, targetStart, effectiveDurationMinutes, ruleEdit, patch
                )
                else -> updateRecurringAllEvents(
                    row, timestamp, targetStart, effectiveDurationMinutes, ruleEdit, patch
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
        // Already in the stored frame (see resolveTargetStart).
        targetStart: Long?,
        durationMinutes: Int?,
        ruleEdit: SeriesRuleEdit,
        patch: EventFieldPatch
    ): Result<String> {
        val values = android.content.ContentValues()
        applyEventFieldValues(values, patch)

        // Recurrence rule column and the resulting recurring state.
        val wasRecurring = row.rrule != null
        val willBeRecurring = when (ruleEdit) {
            SeriesRuleEdit.Clear -> false
            is SeriesRuleEdit.Replace -> true
            is SeriesRuleEdit.Keep -> ruleEdit.rule != null
        }
        when (ruleEdit) {
            SeriesRuleEdit.Clear -> values.putNull(CalendarContract.Events.RRULE)
            is SeriesRuleEdit.Replace -> values.put(CalendarContract.Events.RRULE, ruleEdit.rule)
            is SeriesRuleEdit.Keep -> {}
        }

        // Time columns. A recurring event must use DURATION (and no DTEND); a
        // single event must use DTEND (and no DURATION). Rewrite them when the
        // start, duration, or recurring state changes.
        val effectiveIsAllDay = patch.isAllDay ?: row.allDay
        // The anchor shifts relative to the occurrence the caller pointed at
        // (timestamp), or the series anchor itself when none was given — and
        // then onto the new rule, when one is given (#140).
        val (newStart, newDurationMs) = resolveSeriesTimes(
            baseMillis = row.dtstart,
            referenceMillis = timestamp ?: row.dtstart,
            existingDurationMillis = eventDurationMillis(row),
            targetStart = targetStart,
            durationMinutes = durationMinutes,
            ruleEdit = ruleEdit,
            splitsSeries = false,
            isAllDay = effectiveIsAllDay,
            timeZoneId = row.timeZone,
            storedZone = seriesTimeZone(row.timeZone, row.allDay)
        ).getOrElse { return Result.failure(it) }
        // A `start` equal to the current anchor is still a rewrite: the
        // DTSTART/DURATION (and RRULE, below) re-put is what makes the
        // provider re-expand the series.
        val rewriteTimeColumns = targetStart != null || durationMinutes != null ||
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
                (ruleEdit as? SeriesRuleEdit.Keep)?.rule?.let {
                    values.put(CalendarContract.Events.RRULE, it)
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

        val updatedRows = store.updateEventRow(row.id, values)
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
        // Already in the stored frame (see resolveTargetStart).
        targetStart: Long?,
        durationMinutes: Int?,
        ruleEdit: SeriesRuleEdit,
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
        val effectiveRrule = when (ruleEdit) {
            SeriesRuleEdit.Clear -> null
            is SeriesRuleEdit.Replace -> ruleEdit.rule
            is SeriesRuleEdit.Keep -> {
                // Rule unchanged: the new series inherits the original rule. A
                // COUNT must drop by the occurrences left on the old series,
                // or the new series would over-generate.
                val originalCount = RruleString.count(rrule)
                if (originalCount != null) {
                    val before = countInstancesBefore(row, timestamp)
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
            baseMillis = timestamp,
            referenceMillis = timestamp,
            existingDurationMillis = eventDurationMillis(row),
            targetStart = targetStart,
            durationMinutes = durationMinutes,
            ruleEdit = ruleEdit,
            splitsSeries = true,
            isAllDay = effectiveIsAllDay,
            timeZoneId = row.timeZone,
            storedZone = seriesTimeZone(row.timeZone, row.allDay)
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
        val truncatedRrule = RruleString.withUntil(rrule, timestamp - 1000, row.allDay)
        val truncatedRows =
            store.rewriteSeriesForReexpand(row, truncatedRrule)
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

        // Settled after the truncate, for the reason the delete path sweeps
        // after it (see deleteRecurringThisAndFollowing): a failure here
        // leaves the exceptions on the old series rather than losing them.
        // The split is committed by now, so this is best-effort and reports
        // nothing (see DetachedOccurrenceCarry.settleAfterSplit). A new
        // series moves them as it moved its anchor, in the frame
        // resolveSeriesTimes did above; a new event that doesn't recur
        // drops them.
        val shift = effectiveRrule?.let {
            SplitShift.of(
                timestamp, newStart,
                seriesTimeZone(row.timeZone, effectiveIsAllDay), effectiveIsAllDay
            )
        }
        detachedOccurrenceCarry.settleAfterSplit(row, timestamp, newEventId, shift)

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
                "allEvents" -> deleteEventWithExceptions(eventId, accountOfEventRow(eventId))
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

        val (row, rrule) = store.readRecurringRow(eventId).getOrElse { return Result.failure(it) }

        // Truncate the series so the anchor occurrence and every later one
        // stop generating. UNTIL is inclusive, so cutting one second early
        // drops the anchor too — "this and following" removes the anchor.
        val truncatedRrule = RruleString.withUntil(rrule, timestamp - 1000, row.allDay)
        val updatedRows =
            store.rewriteSeriesForReexpand(row, truncatedRrule)
        if (updatedRows == 0) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.NOT_FOUND,
                    "Event with ID $eventId not found"
                )
            )
        }

        // Swept after the truncate so a failure here degrades to the old
        // orphan state rather than resurrecting edited occurrences: had the
        // exceptions gone first and the truncate then failed, the provider
        // would keep generating the original slots and the user's
        // per-occurrence edits would be lost.
        store.deleteDetachedOccurrencesFrom(row, timestamp)
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
        val series = store.readRecurringRow(eventId).getOrElse { return Result.failure(it) }

        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, timestamp)
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CANCELED)
        }
        return insertException(series, values).map { }
    }

    /**
     * Inserts an exception row carrying [values] against [series]' master:
     * the one write behind every per-occurrence edit or delete. It owns the
     * #153 keying — a local series gets its `_sync_id` here, before the
     * insert — so a future exception writer cannot skip it. Returns the new
     * exception's own event ID.
     *
     * A synced series its adapter has not uploaded yet has no key to give
     * the exception, so the insert is followed by a re-expand of the master
     * (#163): the series stays listed, and the change shows once the adapter
     * keys the master.
     *
     * A plain caller's insert on every account. On a synced calendar that
     * marks the exception DIRTY for the adapter to upload — a cancellation
     * written as the sync adapter never leaves the device, and the next
     * sync brings the occurrence back (#132, #161). A local calendar has no
     * adapter to upload it, and the insert needs none of the adapter's
     * powers (see [SeriesRowStore.deleteUri] for the local writes that do).
     */
    private fun insertException(
        series: SeriesRow,
        values: android.content.ContentValues
    ): Result<String> {
        val key = store.ensureLocalSeriesSyncId(series).getOrElse { return Result.failure(it) }

        val uri = CalendarContract.Events.CONTENT_EXCEPTION_URI
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
        // A zero row count is logged, not failed, unlike the truncate paths:
        // the exception is already written, so failing here would misreport
        // a write that happened, and a master that had vanished would have
        // failed the insert above.
        if (key == null && store.rewriteSeriesForReexpand(series.row, series.rrule) == 0) {
            android.util.Log.w(
                LOG_TAG,
                "Could not re-expand unkeyed series ${series.row.id} after its exception insert (#163)"
            )
        }
        return Result.success(exceptionId)
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
        store.updateEventRow(eventId.toString(), values)
    }

    private fun availabilityToInt(availability: String): Int {
        return when (availability) {
            "free" -> CalendarContract.Events.AVAILABILITY_FREE
            "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
            else -> CalendarContract.Events.AVAILABILITY_BUSY
        }
    }

    /**
     * The INVALID_ARGUMENTS failure for a recurrence [rule] iOS can't store
     * (see [RruleString.hasSupportedFrequency]), or null when [rule] is null
     * or supported.
     */
    private fun unsupportedRuleFailure(rule: String?): CalendarException? =
        rule?.takeUnless(RruleString::hasSupportedFrequency)?.let {
            CalendarException(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Invalid recurrence rule: $it"
            )
        }

    /** Resolves an event's duration, falling back to one hour when unknown. */
    private fun eventDurationMillis(row: EventRow): Long =
        storedEndMillis(row.dtstart, row.dtend, row.duration)?.let { it - row.dtstart } ?: 3_600_000L

    /** Number of occurrences of series [row] that start before [beforeMillis]. */
    private fun countInstancesBefore(row: EventRow, beforeMillis: Long): Int {
        // From the series' own DTSTART, so a series of any age is counted
        // whole: a fixed look-back (five years, once) under-counted an older
        // COUNT series, and its split's new series over-generated (#124).
        // A day early, so an all-day first occurrence, whose UTC-midnight
        // start the provider reads as a local date, can't fall outside it.
        val windowStart = row.dtstart - AllDayDates.MILLIS_PER_DAY
        val uri = EventColumns.instancesUri(windowStart, beforeMillis)
        var count = 0
        context.contentResolver.query(
            uri,
            arrayOf(CalendarContract.Instances.BEGIN),
            "${CalendarContract.Instances.EVENT_ID} = ?",
            arrayOf(row.id),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getLong(0) < beforeMillis) count++
            }
        }
        return count
    }

    /**
     * The account of event row [eventId], for [deleteRecurring]'s `allEvents`
     * span to build its delete from, or null when the row is gone altogether. Reads
     * through a DELETED tombstone on purpose: a local one is still to be
     * collected.
     */
    private fun accountOfEventRow(eventId: String): CalendarAccount? =
        context.contentResolver.query(
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
        }
}
