package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * An all-day series' `start` move on devices either side of UTC (#144).
 * The stored occurrence is UTC midnight; the caller's new start arrives
 * from Dart as the device-local midnight of the day it means, and
 * updateRecurring brings it into the stored frame with [storageMillis]
 * before [dayMoveConflictsWithRule] and [resolveSeriesTimes] see it. These
 * tests make the same calls in the same order. 2026-06-06 is a Saturday.
 */
internal class DayMoveConflictTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val originalDefault = TimeZone.getDefault()

    @AfterTest
    fun restoreDefaultZone() = TimeZone.setDefault(originalDefault)

    /** The June [day]'s all-day occurrence, as the provider stores it. */
    private fun stored(day: Int) = instantAt(utc, 2026, 6, day)

    /**
     * A caller's start on June [day], as Dart sends it from a device in
     * [zoneId], brought into the stored frame as updateRecurring does.
     */
    private fun target(day: Int, zoneId: String): Long {
        val zone = TimeZone.getTimeZone(zoneId)
        TimeZone.setDefault(zone)
        return storageMillis(instantAt(zone, 2026, 6, day), isAllDay = true)
    }

    /** updateRecurring's day-move check for an all-day series whose row names [zoneId]. */
    private fun conflicts(rrule: String, storedDay: Int, newDay: Int, zoneId: String): Boolean {
        val targetStart = target(newDay, zoneId)
        val allDayZone = seriesTimeZone(zoneId, isAllDay = true)
        return dayMoveConflictsWithRule(rrule, stored(storedDay), allDayZone, targetStart, allDayZone)
    }

    // West of UTC the stored UTC midnight is the previous local evening:
    // read in the device zone it looked like a Friday, so keeping the
    // Saturday was refused and moving to the Friday let through.
    @Test
    fun dayMoveConflictsWithRule_allDaySameDayWestOfUtc_noConflict() {
        assertFalse(conflicts("FREQ=WEEKLY;BYDAY=SA", 6, 6, "America/Los_Angeles"))
    }

    @Test
    fun dayMoveConflictsWithRule_allDayDayEarlierWestOfUtc_conflicts() {
        assertTrue(conflicts("FREQ=WEEKLY;BYDAY=SA", 6, 5, "America/Los_Angeles"))
    }

    @Test
    fun dayMoveConflictsWithRule_allDayMonthDayMoveWestOfUtc_conflicts() {
        assertTrue(conflicts("FREQ=MONTHLY;BYMONTHDAY=6", 6, 5, "America/Los_Angeles"))
    }

    @Test
    fun dayMoveConflictsWithRule_allDaySameDayEastOfUtc_noConflict() {
        assertFalse(conflicts("FREQ=WEEKLY;BYDAY=SA", 6, 6, "Australia/Sydney"))
    }

    @Test
    fun dayMoveConflictsWithRule_allDayDayLaterEastOfUtc_conflicts() {
        assertTrue(conflicts("FREQ=WEEKLY;BYDAY=SA", 6, 7, "Australia/Sydney"))
    }

    // East of UTC a local midnight is the previous UTC day: read in UTC
    // unconverted, a one-day move counted zero days and left the series put.
    @Test
    fun resolveSeriesTimes_allDayDayLaterEastOfUtc_movesOneDay() {
        val targetStart = target(7, "Australia/Sydney")
        val (newStart, _) = resolveSeriesTimes(
            baseMillis = stored(6),
            referenceMillis = stored(6),
            existingDurationMillis = 86_400_000L,
            newStartMillis = targetStart,
            durationMinutes = null,
            rrule = null,
            timeZoneId = "Australia/Sydney",
            isAllDay = true
        ).getOrThrow()
        assertEquals(stored(7), newStart)
    }

    @Test
    fun resolveSeriesTimes_allDayDayLaterWestOfUtc_movesOneDay() {
        val targetStart = target(7, "America/Los_Angeles")
        val (newStart, _) = resolveSeriesTimes(
            baseMillis = stored(6),
            referenceMillis = stored(6),
            existingDurationMillis = 86_400_000L,
            newStartMillis = targetStart,
            durationMinutes = null,
            rrule = null,
            timeZoneId = "America/Los_Angeles",
            isAllDay = true
        ).getOrThrow()
        assertEquals(stored(7), newStart)
    }
}
