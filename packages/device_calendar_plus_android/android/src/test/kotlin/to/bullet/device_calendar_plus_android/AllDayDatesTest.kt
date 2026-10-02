package to.bullet.device_calendar_plus_android

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
    private val zones = listOf(sydney, losAngeles)
    private val utc = TimeZone.getTimeZone("UTC")

    // End on a local midnight keeps the boundary (exclusive end).
    @Test
    fun windowEndUtcMidnight_endOnLocalMidnight_isThatDatesUtcMidnight() {
        for (zone in zones) {
            val end = AllDayDates.windowEndUtcMidnight(instantAt(zone, 2026, 9, 26), zone)
            assertEquals(instantAt(utc, 2026, 9, 26), end, zone.id)
        }
    }

    // End inside a date covers that date.
    @Test
    fun windowEndUtcMidnight_endInsideDate_roundsUpToNextUtcMidnight() {
        for (zone in zones) {
            val end = AllDayDates.windowEndUtcMidnight(instantAt(zone, 2026, 9, 26, 11), zone)
            assertEquals(instantAt(utc, 2026, 9, 27), end, zone.id)
        }
    }

    // The first instant past midnight is inside the new date, so it covers it.
    @Test
    fun windowEndUtcMidnight_endJustAfterLocalMidnight_roundsUp() {
        for (zone in zones) {
            val end = AllDayDates.windowEndUtcMidnight(instantAt(zone, 2026, 9, 26) + 1, zone)
            assertEquals(instantAt(utc, 2026, 9, 27), end, zone.id)
        }
    }

    private val oneDayMinutes = 24 * 60
    private val hour = 3_600_000L

    // A timed event inside one local date toggles to that one day.
    @Test
    fun toggleDurationMinutes_withinOneDate_isOneDay() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26, 0, 30)
            assertEquals(oneDayMinutes, AllDayDates.toggleDurationMinutes(start, hour, zone), zone.id)
        }
    }

    // An event running past local midnight spans both dates it touches.
    @Test
    fun toggleDurationMinutes_crossingLocalMidnight_isTwoDays() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26, 23, 30)
            assertEquals(2 * oneDayMinutes, AllDayDates.toggleDurationMinutes(start, hour, zone), zone.id)
        }
    }

    // An event ending exactly on local midnight doesn't touch the next date.
    @Test
    fun toggleDurationMinutes_endingOnLocalMidnight_isOneDay() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26, 23)
            assertEquals(oneDayMinutes, AllDayDates.toggleDurationMinutes(start, hour, zone), zone.id)
        }
    }

    // A zero-length event still takes its one day.
    @Test
    fun toggleDurationMinutes_zeroLength_isOneDay() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26)
            assertEquals(oneDayMinutes, AllDayDates.toggleDurationMinutes(start, 0L, zone), zone.id)
        }
    }
}
