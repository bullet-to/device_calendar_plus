package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * `AllDayDates.windowEndUtcMidnight` is the exclusive all-day edge of a
 * listEvents window: the UTC midnight after the local date of `end - 1`, so
 * a sub-day window still covers its whole date (#20).
 *
 * `AllDayDates.toggleSpan` is the all-day span a timed event takes when an
 * edit toggles it all-day without new dates: UTC midnight of its local date,
 * through one day for every local date it touches, and at least one.
 *
 * `AllDayDates.timedSpan` is the reverse: the timed span an all-day event
 * takes when an edit toggles it timed, from local midnight of its first
 * date to the last second of its last.
 */
internal class AllDayDatesTest {
    // One zone each side of UTC: Sydney's local midnight lands on the previous
    // UTC date, Los Angeles's on the same UTC date, so a rounding slip shows
    // up in one hemisphere even if it cancels out in the other.
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")
    private val losAngeles = TimeZone.getTimeZone("America/Los_Angeles")
    private val zones = listOf(sydney, losAngeles)
    private val utc = TimeZone.getTimeZone("UTC")
    private val hour = 3_600_000L

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

    // A timed event inside one local date toggles to that one day.
    @Test
    fun toggleSpan_withinOneDate_isThatOneDay() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26, 0, 30)
            val expected = instantAt(utc, 2026, 9, 26) to instantAt(utc, 2026, 9, 27)
            assertEquals(expected, AllDayDates.toggleSpan(start, hour, zone), zone.id)
        }
    }

    // An event running past local midnight spans both dates it touches.
    @Test
    fun toggleSpan_crossingLocalMidnight_isBothDays() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26, 23, 30)
            val expected = instantAt(utc, 2026, 9, 26) to instantAt(utc, 2026, 9, 28)
            assertEquals(expected, AllDayDates.toggleSpan(start, hour, zone), zone.id)
        }
    }

    // An event ending exactly on local midnight doesn't touch the next date.
    @Test
    fun toggleSpan_endingOnLocalMidnight_isOneDay() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26, 23)
            val expected = instantAt(utc, 2026, 9, 26) to instantAt(utc, 2026, 9, 27)
            assertEquals(expected, AllDayDates.toggleSpan(start, hour, zone), zone.id)
        }
    }

    // A zero-length event still takes its one day.
    @Test
    fun toggleSpan_zeroLength_isOneDay() {
        for (zone in zones) {
            val start = instantAt(zone, 2026, 9, 26)
            val expected = instantAt(utc, 2026, 9, 26) to instantAt(utc, 2026, 9, 27)
            assertEquals(expected, AllDayDates.toggleSpan(start, 0L, zone), zone.id)
        }
    }

    // A stored all-day date toggles timed to the device's own day: local
    // midnight through the last second before the next local midnight.
    @Test
    fun timedSpan_oneDay_isThatLocalDay() {
        for (zone in zones + utc) {
            val expected = instantAt(zone, 2026, 9, 26) to
                instantAt(zone, 2026, 9, 27) - 1_000L
            assertEquals(
                expected,
                AllDayDates.timedSpan(instantAt(utc, 2026, 9, 26), DAY, zone),
                zone.id
            )
        }
    }

    // Across a DST change the end is still a second before the local
    // midnight, not a fixed 48 hours on: Sydney springs forward on 4
    // October 2026, Los Angeles falls back on 1 November.
    @Test
    fun timedSpan_acrossDst_endsBeforeTheLocalMidnight() {
        val sydneyDays = AllDayDates.timedSpan(instantAt(utc, 2026, 10, 3), 2 * DAY, sydney)
        assertEquals(
            instantAt(sydney, 2026, 10, 3) to instantAt(sydney, 2026, 10, 5) - 1_000L,
            sydneyDays
        )
        val laDays = AllDayDates.timedSpan(instantAt(utc, 2026, 10, 31), 2 * DAY, losAngeles)
        assertEquals(
            instantAt(losAngeles, 2026, 10, 31) to instantAt(losAngeles, 2026, 11, 2) - 1_000L,
            laDays
        )
    }

    // An empty all-day span ends where it starts, not a second before.
    @Test
    fun timedSpan_zeroLength_endsAtTheStart() {
        for (zone in zones + utc) {
            val start = instantAt(zone, 2026, 9, 26)
            assertEquals(
                start to start,
                AllDayDates.timedSpan(instantAt(utc, 2026, 9, 26), 0L, zone),
                zone.id
            )
        }
    }

    private companion object {
        const val DAY = AllDayDates.MILLIS_PER_DAY
    }
}
