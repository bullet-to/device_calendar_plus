package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * [SplitShift] moves a series' slots by the whole calendar days its anchor
 * moved, and a detached occurrence's start by the whole 24h wall-clock days
 * in the shift, both in the series' zone, never by the raw millisecond
 * shift: across a DST change the two differ by an hour (#158). New York's 2026 transitions are
 * March 8 (spring forward) and November 1 (fall back).
 */
internal class SplitShiftTest {
    private val newYork = TimeZone.getTimeZone("America/New_York")
    private val utc = TimeZone.getTimeZone("UTC")

    private fun ny(month: Int, day: Int, hour: Int, minute: Int = 0) =
        instantAt(newYork, 2026, month, day, hour, minute)

    /** A shift with no all-day toggle, which most cases here are. */
    private fun untoggled(from: Long, to: Long, tz: TimeZone, isAllDay: Boolean) =
        SplitShift.of(from, to, tz, isAllDay, FrameChange.None)

    // Anchor moved two days on, same time. A slot past the fall-back keeps
    // its 9:00 wall-clock time; the raw 48h shift would land at 8:00.
    @Test
    fun slot_acrossFallBack_keepsWallClockTime() {
        val shift = untoggled(ny(10, 1, 9), ny(10, 3, 9), newYork, isAllDay = false)
        assertEquals(ny(11, 2, 9), shift.slot(ny(10, 31, 9)))
    }

    @Test
    fun slot_acrossSpringForward_keepsWallClockTime() {
        val shift = untoggled(ny(3, 1, 9), ny(3, 3, 9), newYork, isAllDay = false)
        assertEquals(ny(3, 9, 9), shift.slot(ny(3, 7, 9)))
    }

    // A slot takes the new anchor's time of day, not its own.
    @Test
    fun slot_takesNewAnchorsTimeOfDay() {
        val shift = untoggled(ny(10, 1, 9), ny(10, 3, 11, 15), newYork, isAllDay = false)
        assertEquals(ny(11, 2, 11, 15), shift.slot(ny(10, 31, 9)))
    }

    // A detached occurrence's start keeps its own time of day, moved only by
    // the days, across the fall-back too.
    @Test
    fun start_keepsOwnTimeOfDay() {
        val shift = untoggled(ny(10, 1, 9), ny(10, 3, 11, 15), newYork, isAllDay = false)
        assertEquals(ny(11, 2, 14, 30), shift.start(ny(10, 31, 14, 30)))
    }

    // Moving the anchor back moves the series back, onto the fall-back day.
    @Test
    fun slotAndStart_negativeDelta_moveBack() {
        val shift = untoggled(ny(10, 3, 9), ny(10, 1, 9), newYork, isAllDay = false)
        assertEquals(ny(11, 1, 9), shift.slot(ny(11, 3, 9)))
        assertEquals(ny(11, 1, 16), shift.start(ny(11, 3, 16)))
    }

    // All-day series live in UTC at midnight: whole days, time left at 0:00.
    @Test
    fun slotAndStart_allDayInUtc_moveByWholeDaysAtMidnight() {
        val shift = untoggled(
            instantAt(utc, 2026, 6, 5), instantAt(utc, 2026, 6, 6), utc, isAllDay = true
        )
        assertEquals(instantAt(utc, 2026, 6, 11), shift.slot(instantAt(utc, 2026, 6, 10)))
        assertEquals(instantAt(utc, 2026, 6, 11), shift.start(instantAt(utc, 2026, 6, 10)))
    }

    // A sub-day shift across the series zone's midnight: 23:30 to 00:30 the
    // next day is one calendar day but under 24h. The slots move to the next
    // day at 00:30, as the new series generates them, but a detached
    // occurrence's own start moves by the whole 24h days in the shift, none
    // here, as EventKit moves it (#224).
    @Test
    fun start_subDayShiftAcrossMidnight_keepsTheOccurrencesStart() {
        val shift = untoggled(
            instantAt(utc, 2026, 6, 4, 23, 30), instantAt(utc, 2026, 6, 5, 0, 30),
            utc, isAllDay = false,
        )
        assertEquals(instantAt(utc, 2026, 6, 8, 0, 30), shift.slot(instantAt(utc, 2026, 6, 7, 23, 30)))
        assertEquals(instantAt(utc, 2026, 6, 8, 1, 30), shift.start(instantAt(utc, 2026, 6, 8, 1, 30)))
    }

    // Back across midnight, 00:30 to 23:30 the day before, is under 24h too.
    @Test
    fun start_negativeSubDayShiftAcrossMidnight_keepsTheOccurrencesStart() {
        val shift = untoggled(
            instantAt(utc, 2026, 6, 5, 0, 30), instantAt(utc, 2026, 6, 4, 23, 30),
            utc, isAllDay = false,
        )
        assertEquals(instantAt(utc, 2026, 6, 7, 23, 30), shift.slot(instantAt(utc, 2026, 6, 8, 0, 30)))
        assertEquals(instantAt(utc, 2026, 6, 8, 2, 30), shift.start(instantAt(utc, 2026, 6, 8, 2, 30)))
    }

    // 14:00 to 15:00 the next day is a whole 24h day and an hour: one day.
    @Test
    fun start_shiftOfMoreThanADay_movesTheOccurrenceByItsWholeDays() {
        val shift = untoggled(
            instantAt(utc, 2026, 6, 4, 14), instantAt(utc, 2026, 6, 5, 15),
            utc, isAllDay = false,
        )
        assertEquals(instantAt(utc, 2026, 6, 9, 16), shift.start(instantAt(utc, 2026, 6, 8, 16)))
    }

    // Read on the wall clock, a shift across a DST change still counts its
    // whole days: 9:00 to 9:30 three days on, across the spring-forward, is
    // three days and half an hour on the clock but only 71h30m elapsed,
    // which counted raw would be two days.
    @Test
    fun start_shiftAcrossSpringForward_countsWallClockDays() {
        val shift = untoggled(ny(3, 6, 9), ny(3, 9, 9, 30), newYork, isAllDay = false)
        assertEquals(ny(3, 13, 16), shift.start(ny(3, 10, 16)))
    }

    // A toggle to timed counts the calendar days, as before #224: the
    // converted anchor sits at New York midnight on June 5, so a move back
    // to 9:00 on June 4 is one calendar day back, though on the wall clock
    // it is only 15h (which truncated would be no days).
    @Test
    fun start_toTimedToggleMovedBack_countsCalendarDays() {
        val shift = SplitShift.of(
            instantAt(utc, 2026, 6, 5), ny(6, 4, 9), newYork,
            isAllDay = false, frameChange = FrameChange.ToTimed(newYork),
        )
        assertEquals(instantAt(utc, 2026, 6, 9), shift.start(instantAt(utc, 2026, 6, 10)))
    }

    // A toggle to all-day reads the wall-clock shift, which is the
    // calendar-day count here: the series zone is UTC and both anchors sit
    // at UTC midnight. 21:00 on June 4 in New York is June 5 in UTC, but
    // the toggle keeps its New York date, so the anchor moves two days, and
    // a slot (a stored timed instant, toggled the same way) and an all-day
    // occurrence's start both move two days with it.
    @Test
    fun start_toAllDayToggle_countsCalendarDays() {
        val shift = SplitShift.of(
            ny(6, 4, 21), instantAt(utc, 2026, 6, 6), utc,
            isAllDay = true, frameChange = FrameChange.ToAllDay(newYork),
        )
        assertEquals(instantAt(utc, 2026, 6, 12), shift.slot(ny(6, 10, 21)))
        assertEquals(instantAt(utc, 2026, 6, 12), shift.start(instantAt(utc, 2026, 6, 10)))
    }

    // No move leaves every date where it was.
    @Test
    fun slotAndStart_sameAnchor_areIdentity() {
        val shift = untoggled(ny(10, 1, 9), ny(10, 1, 9), newYork, isAllDay = false)
        assertEquals(ny(10, 31, 9), shift.slot(ny(10, 31, 9)))
        assertEquals(ny(10, 31, 14, 30), shift.start(ny(10, 31, 14, 30)))
    }
}
