package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract

/**
 * Column-name preset for `EventsService.buildEventMapFromCursor`.
 *
 * The Instances and Events content URIs expose the same event data under
 * different column names (EVENT_ID vs _ID, BEGIN vs DTSTART, ...). Each query
 * picks the matching preset and derives its projection from it, so the
 * projection and the cursor reads can't silently diverge. Adding a read-only
 * field is a handful of colocated edits — the property, the preset value, the
 * projection entry, and the read in buildEventMapFromCursor — each either
 * compile-enforced (no default args) or loud at runtime
 * (getColumnIndexOrThrow), instead of scattered call-site edits that could
 * silently drift apart.
 */
internal data class EventColumns(
    val eventId: String,
    val calendarId: String,
    val title: String,
    val description: String,
    val location: String,
    val start: String,
    val end: String,
    val allDay: String,
    val availability: String,
    val status: String,
    val timeZone: String,
    val recurrenceRule: String,
    val url: String,
    val eventColor: String,
) {
    /** Query projection covering every column this preset reads. */
    val projection: Array<String> = arrayOf(
        eventId,
        calendarId,
        title,
        description,
        location,
        start,
        end,
        allDay,
        availability,
        status,
        timeZone,
        recurrenceRule,
        url,
        eventColor,
    )

    companion object {
        /** Columns for [CalendarContract.Events] queries (master event rows). */
        val events = EventColumns(
            eventId = CalendarContract.Events._ID,
            calendarId = CalendarContract.Events.CALENDAR_ID,
            title = CalendarContract.Events.TITLE,
            description = CalendarContract.Events.DESCRIPTION,
            location = CalendarContract.Events.EVENT_LOCATION,
            start = CalendarContract.Events.DTSTART,
            end = CalendarContract.Events.DTEND,
            allDay = CalendarContract.Events.ALL_DAY,
            availability = CalendarContract.Events.AVAILABILITY,
            status = CalendarContract.Events.STATUS,
            timeZone = CalendarContract.Events.EVENT_TIMEZONE,
            recurrenceRule = CalendarContract.Events.RRULE,
            url = CalendarContract.Events.CUSTOM_APP_URI,
            eventColor = CalendarContract.Events.EVENT_COLOR,
        )

        /**
         * Columns for [CalendarContract.Instances] queries (expanded
         * occurrences). The Instances URI shares the Events column names
         * (Instances implements EventsColumns) except for the row ID and the
         * occurrence window, so only those three differ from [events].
         */
        val instances = events.copy(
            eventId = CalendarContract.Instances.EVENT_ID,
            start = CalendarContract.Instances.BEGIN,
            end = CalendarContract.Instances.END,
        )
    }
}
