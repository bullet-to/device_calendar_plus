package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * `AllDayDates.windowEndUtcMidnight` is the exclusive all-day edge of a
 * listEvents window: the UTC midnight after the local date of `end - 1`, so
 * a sub-day window still covers its whole date (#20).
 */
internal class AllDayDatesTest {
    // One zone each side of UTC: Sydney's local midnight lands on the previous
    // UTC date, Los Angeles's on the same UTC date, so a rounding slip shows
    // up in one hemisphere even if it cancels out in the other.
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")
    private val losAngeles = TimeZone.getTimeZone("America/Los_Angeles")
    private val utc = TimeZone.getTimeZone("UTC")

    private fun at(zone: TimeZone, year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, hour, minute, 0)
        }.timeInMillis

    // End on a local midnight keeps the boundary (exclusive end).
    @Test
    fun windowEndUtcMidnight_endOnLocalMidnight_isThatDatesUtcMidnight() {
        val end = AllDayDates.windowEndUtcMidnight(at(sydney, 2026, 9, 26), sydney)
        assertEquals(at(utc, 2026, 9, 26), end)
    }

    // End inside a date covers that date.
    @Test
    fun windowEndUtcMidnight_endInsideDate_roundsUpToNextUtcMidnight() {
        val end = AllDayDates.windowEndUtcMidnight(at(sydney, 2026, 9, 26, 11), sydney)
        assertEquals(at(utc, 2026, 9, 27), end)
    }

    // The first instant past midnight is inside the new date, so it covers it.
    @Test
    fun windowEndUtcMidnight_endJustAfterLocalMidnight_roundsUp() {
        val end = AllDayDates.windowEndUtcMidnight(at(sydney, 2026, 9, 26) + 1, sydney)
        assertEquals(at(utc, 2026, 9, 27), end)
    }

    @Test
    fun windowEndUtcMidnight_endOnLocalMidnight_westOfUtc_isThatDatesUtcMidnight() {
        val end = AllDayDates.windowEndUtcMidnight(at(losAngeles, 2026, 9, 26), losAngeles)
        assertEquals(at(utc, 2026, 9, 26), end)
    }

    @Test
    fun windowEndUtcMidnight_endInsideDate_westOfUtc_roundsUpToNextUtcMidnight() {
        val end = AllDayDates.windowEndUtcMidnight(at(losAngeles, 2026, 9, 26, 11), losAngeles)
        assertEquals(at(utc, 2026, 9, 27), end)
    }
}
