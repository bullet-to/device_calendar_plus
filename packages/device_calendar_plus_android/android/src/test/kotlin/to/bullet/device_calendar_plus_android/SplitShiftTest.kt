package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * [SplitShift] moves a series by the whole calendar days its anchor moved,
 * in the series' zone, never by the raw millisecond shift: across a DST
 * change the two differ by an hour (#158). New York's 2026 transitions are
 * March 8 (spring forward) and November 1 (fall back).
 */
internal class SplitShiftTest {
    private val newYork = TimeZone.getTimeZone("America/New_York")
    private val utc = TimeZone.getTimeZone("UTC")

    private fun ny(month: Int, day: Int, hour: Int, minute: Int = 0) =
        instantAt(newYork, 2026, month, day, hour, minute)

    // Anchor moved two days on, same time. A slot past the fall-back keeps
    // its 9:00 wall-clock time; the raw 48h shift would land at 8:00.
    @Test
    fun slot_acrossFallBack_keepsWallClockTime() {
        val shift = SplitShift.of(ny(10, 1, 9), ny(10, 3, 9), newYork, isAllDay = false)
        assertEquals(ny(11, 2, 9), shift.slot(ny(10, 31, 9)))
    }

    @Test
    fun slot_acrossSpringForward_keepsWallClockTime() {
        val shift = SplitShift.of(ny(3, 1, 9), ny(3, 3, 9), newYork, isAllDay = false)
        assertEquals(ny(3, 9, 9), shift.slot(ny(3, 7, 9)))
    }

    // A slot takes the new anchor's time of day, not its own.
    @Test
    fun slot_takesNewAnchorsTimeOfDay() {
        val shift = SplitShift.of(ny(10, 1, 9), ny(10, 3, 11, 15), newYork, isAllDay = false)
        assertEquals(ny(11, 2, 11, 15), shift.slot(ny(10, 31, 9)))
    }

    // A detached occurrence's start keeps its own time of day, moved only by
    // the days, across the fall-back too.
    @Test
    fun start_keepsOwnTimeOfDay() {
        val shift = SplitShift.of(ny(10, 1, 9), ny(10, 3, 11, 15), newYork, isAllDay = false)
        assertEquals(ny(11, 2, 14, 30), shift.start(ny(10, 31, 14, 30)))
    }

    // Moving the anchor back moves the series back, onto the fall-back day.
    @Test
    fun slotAndStart_negativeDelta_moveBack() {
        val shift = SplitShift.of(ny(10, 3, 9), ny(10, 1, 9), newYork, isAllDay = false)
        assertEquals(ny(11, 1, 9), shift.slot(ny(11, 3, 9)))
        assertEquals(ny(11, 1, 16), shift.start(ny(11, 3, 16)))
    }

    // All-day series live in UTC at midnight: whole days, time left at 0:00.
    @Test
    fun slotAndStart_allDayInUtc_moveByWholeDaysAtMidnight() {
        val shift = SplitShift.of(
            instantAt(utc, 2026, 6, 5), instantAt(utc, 2026, 6, 6), utc, isAllDay = true
        )
        assertEquals(instantAt(utc, 2026, 6, 11), shift.slot(instantAt(utc, 2026, 6, 10)))
        assertEquals(instantAt(utc, 2026, 6, 11), shift.start(instantAt(utc, 2026, 6, 10)))
    }

    // No move leaves every date where it was.
    @Test
    fun slotAndStart_sameAnchor_areIdentity() {
        val shift = SplitShift.of(ny(10, 1, 9), ny(10, 1, 9), newYork, isAllDay = false)
        assertEquals(ny(10, 31, 9), shift.slot(ny(10, 31, 9)))
        assertEquals(ny(10, 31, 14, 30), shift.start(ny(10, 31, 14, 30)))
    }
}
