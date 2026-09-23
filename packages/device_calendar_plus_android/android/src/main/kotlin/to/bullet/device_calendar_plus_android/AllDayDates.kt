package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

/**
 * Date arithmetic for all-day events.
 *
 * Android stores all-day events as UTC midnight boundaries, so a local
 * "June 5" must become "June 5 00:00 UTC" on the way in and come back as the
 * device's local midnight on the way out. These conversions are pure
 * functions of an instant and a zone; the caller names the zone so the
 * boundary is explicit (and testable without a device).
 */
internal object AllDayDates {
    const val MILLIS_PER_DAY = 86_400_000L

    /**
     * Converts local-time millis to UTC midnight, preserving the calendar
     * date. Used both when writing all-day events and for the all-day edges
     * of the listEvents window (see [windowEndUtcMidnight]).
     */
    fun localDateToUtcMidnight(localMillis: Long, zone: TimeZone): Long {
        val local = Calendar.getInstance(zone)
        local.timeInMillis = localMillis
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        utc.set(
            local.get(Calendar.YEAR),
            local.get(Calendar.MONTH),
            local.get(Calendar.DAY_OF_MONTH),
            0, 0, 0
        )
        utc.set(Calendar.MILLISECOND, 0)
        return utc.timeInMillis
    }

    /**
     * Converts UTC millis to local midnight, preserving the calendar date.
     * Used when reading all-day events, to present the stored UTC date in
     * the device's local time.
     */
    fun utcToLocalMidnight(utcMillis: Long, zone: TimeZone): Long {
        val utcCal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        utcCal.timeInMillis = utcMillis
        val localCal = Calendar.getInstance(zone)
        localCal.set(
            utcCal.get(Calendar.YEAR),
            utcCal.get(Calendar.MONTH),
            utcCal.get(Calendar.DAY_OF_MONTH),
            0, 0, 0
        )
        localCal.set(Calendar.MILLISECOND, 0)
        return localCal.timeInMillis
    }

    /**
     * Exclusive UTC-midnight edge of a `[start, end)` listEvents window.
     *
     * All-day events are stored as UTC-midnight dates, but the caller passes
     * local millis. A window touches every local date from `date(start)`
     * through `date(end - 1)`, so its all-day edges are the UTC midnights of
     * those two dates: the start edge is `localDateToUtcMidnight(start)`, and
     * this is the day after the local date of `end - 1`. An end on a local
     * midnight names that boundary unchanged; an end inside a date rounds up
     * so a sub-day window still covers its whole date. (issue #20)
     */
    fun windowEndUtcMidnight(endMillis: Long, zone: TimeZone): Long =
        localDateToUtcMidnight(endMillis - 1, zone) + MILLIS_PER_DAY
}
