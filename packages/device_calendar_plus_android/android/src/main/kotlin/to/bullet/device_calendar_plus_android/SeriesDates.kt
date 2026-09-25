package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

/**
 * The time zone that frames a series' calendar days: the event's own
 * (device default when [timeZoneId] is null), except that all-day events
 * are stored as UTC midnight and so live in UTC.
 */
internal fun seriesTimeZone(timeZoneId: String?, isAllDay: Boolean): TimeZone =
    when {
        isAllDay -> TimeZone.getTimeZone("UTC")
        timeZoneId != null -> TimeZone.getTimeZone(timeZoneId)
        else -> TimeZone.getDefault()
    }

/**
 * Whole calendar days from [fromMillis] to [toMillis] in [tz]. Rounds the
 * start-of-day difference so a DST transition (a 23- or 25-hour day) still
 * yields an integer day count.
 */
internal fun calendarDaysBetween(fromMillis: Long, toMillis: Long, tz: TimeZone): Int {
    val diff = AllDayDates.localMidnight(toMillis, tz) - AllDayDates.localMidnight(fromMillis, tz)
    return Math.round(diff.toDouble() / AllDayDates.MILLIS_PER_DAY).toInt()
}

/**
 * A series' anchor moved from one instant to another, as a rule for moving
 * the rest of the series with it: by the whole calendar days the anchor
 * moved, counted in the series' time zone [tz] (see [seriesTimeZone]). Not
 * by the raw millisecond shift, which a DST change between the anchor and
 * a later date would put an hour off. The anchor-shift that lets
 * [EventsService.updateRecurring] move both the time and the day of a
 * series (#103), and where a `thisAndFollowing` split carries what it
 * carries (#158); iOS's counterparts are `shiftStart` and EKSpan.futureEvents.
 *
 * [slot] is where a date lands on the moved series: that many days on, at
 * the new anchor's wall-clock time of day (midnight for all-day, which is
 * stored as UTC midnight). [start] is where a detached occurrence's own
 * start goes: that many days on, at its own time of day.
 */
internal class SplitShift private constructor(
    private val dayDelta: Int,
    private val tz: TimeZone,
    private val hour: Int,
    private val minute: Int,
    private val second: Int,
    private val millisecond: Int,
) {

    /** [old] moved by the anchor's days, at the new anchor's time of day. */
    fun slot(old: Long): Long {
        val cal = addDays(old)
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, second)
        cal.set(Calendar.MILLISECOND, millisecond)
        return cal.timeInMillis
    }

    /** [old] moved by the anchor's days, keeping its own time of day. */
    fun start(old: Long): Long = addDays(old).timeInMillis

    private fun addDays(millis: Long): Calendar =
        Calendar.getInstance(tz).apply {
            timeInMillis = millis
            add(Calendar.DAY_OF_YEAR, dayDelta)
        }

    companion object {
        /**
         * The shift that moves the anchor [fromAnchor] to [toAnchor], in
         * the series' time zone [tz]. All-day series shift by whole days
         * with the time of day left at midnight; timed ones carry the full
         * wall-clock time of day (down to millis) from [toAnchor], matching
         * iOS's shiftStart so the platforms agree.
         */
        fun of(fromAnchor: Long, toAnchor: Long, tz: TimeZone, isAllDay: Boolean): SplitShift {
            val target = Calendar.getInstance(tz).apply { timeInMillis = toAnchor }
            return SplitShift(
                dayDelta = calendarDaysBetween(fromAnchor, toAnchor, tz),
                tz = tz,
                hour = if (isAllDay) 0 else target.get(Calendar.HOUR_OF_DAY),
                minute = if (isAllDay) 0 else target.get(Calendar.MINUTE),
                second = if (isAllDay) 0 else target.get(Calendar.SECOND),
                millisecond = if (isAllDay) 0 else target.get(Calendar.MILLISECOND),
            )
        }
    }
}
