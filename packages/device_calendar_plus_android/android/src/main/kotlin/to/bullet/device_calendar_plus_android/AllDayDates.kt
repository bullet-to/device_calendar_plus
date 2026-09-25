package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

/**
 * Date arithmetic for all-day events.
 *
 * Android stores all-day events as UTC midnight boundaries, so a local
 * "June 5" must become "June 5 00:00 UTC" on the way in and come back as the
 * device's local midnight on the way out. These conversions are pure
 * functions of an instant and a zone. Production callers take the device's
 * default zone (read per call, so a runtime zone change is picked up); the
 * parameter exists so the unit tests can drive both hemispheres without a
 * device.
 *
 * Every converter is [midnightOfSameDate] with a pair of zones, so this is
 * also the module's one Calendar-based date floor: recurrence code that
 * counts calendar days reuses it through [localMidnight].
 */
internal object AllDayDates {
    const val MILLIS_PER_DAY = 86_400_000L

    private val UTC: TimeZone = TimeZone.getTimeZone("UTC")

    /**
     * Converts local-time millis to UTC midnight, preserving the calendar
     * date. Used both when writing all-day events and for the all-day edges
     * of the listEvents window (see [windowEndUtcMidnight]).
     */
    fun localDateToUtcMidnight(localMillis: Long, zone: TimeZone = TimeZone.getDefault()): Long =
        midnightOfSameDate(localMillis, readIn = zone, writeIn = UTC)

    /**
     * Converts UTC millis to local midnight, preserving the calendar date.
     * Used when reading all-day events, to present the stored UTC date in
     * the device's local time.
     */
    fun utcToLocalMidnight(utcMillis: Long, zone: TimeZone = TimeZone.getDefault()): Long =
        midnightOfSameDate(utcMillis, readIn = UTC, writeIn = zone)

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
    fun windowEndUtcMidnight(endMillis: Long, zone: TimeZone = TimeZone.getDefault()): Long =
        localDateToUtcMidnight(endMillis - 1, zone) + MILLIS_PER_DAY

    /**
     * Midnight, in [zone], of the calendar date that [millis] falls on in
     * [zone]: the start of that instant's local day. Not an all-day
     * conversion; the recurrence anchor shift uses it to count whole
     * calendar days across a DST transition.
     */
    fun localMidnight(millis: Long, zone: TimeZone = TimeZone.getDefault()): Long =
        midnightOfSameDate(millis, readIn = zone, writeIn = zone)

    /**
     * Midnight, in [writeIn], of the calendar date that [millis] falls on in
     * [readIn]. The public converters are this with the zones chosen.
     */
    private fun midnightOfSameDate(millis: Long, readIn: TimeZone, writeIn: TimeZone): Long {
        val source = Calendar.getInstance(readIn)
        source.timeInMillis = millis
        val target = Calendar.getInstance(writeIn)
        target.set(
            source.get(Calendar.YEAR),
            source.get(Calendar.MONTH),
            source.get(Calendar.DAY_OF_MONTH),
            0, 0, 0
        )
        target.set(Calendar.MILLISECOND, 0)
        return target.timeInMillis
    }
}
