package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * `RecurrenceAnchor.firstMatch` picks the DTSTART for a rule change: the
 * first day on or after the intended anchor that the new rule generates,
 * keeping the anchor's wall-clock time in the event's timezone (#140).
 */
internal class RecurrenceAnchorTest {
    private val stockholm = TimeZone.getTimeZone("Europe/Stockholm")

    private fun at(
        year: Int, month: Int, day: Int, hour: Int = 10, minute: Int = 0,
        tz: TimeZone = stockholm
    ): Long = Calendar.getInstance(tz).apply {
        clear()
        set(year, month - 1, day, hour, minute, 0)
    }.timeInMillis

    // The #140 report: a Saturday series switched to Sundays must anchor on
    // the Sunday after the split occurrence, not stay on the Saturday.
    @Test
    fun weeklyByDay_anchorOffRule_movesToNextListedWeekday() {
        val saturday = at(2026, 9, 12)
        assertEquals(
            at(2026, 9, 13),
            RecurrenceAnchor.firstMatch(
                "FREQ=WEEKLY;INTERVAL=1;BYDAY=SU;WKST=MO;UNTIL=20261001T215959Z",
                saturday, stockholm
            )
        )
    }

    @Test
    fun monthlyByMonthDay_pastThisMonthsDay_movesToNextMonth() {
        assertEquals(
            at(2026, 10, 15),
            RecurrenceAnchor.firstMatch("FREQ=MONTHLY;BYMONTHDAY=15", at(2026, 9, 20), stockholm)
        )
    }

    // Negative BYMONTHDAY counts back from the end of the month.
    @Test
    fun monthlyByMonthDay_negative_movesToLastDayOfMonth() {
        assertEquals(
            at(2026, 9, 30),
            RecurrenceAnchor.firstMatch("FREQ=MONTHLY;BYMONTHDAY=-1", at(2026, 9, 12), stockholm)
        )
    }

    // September 2026's second Tuesday (the 8th) is already past, so the
    // anchor lands on October's (the 13th).
    @Test
    fun monthlyByDayOrdinal_movesToNthWeekdayOfNextMonth() {
        assertEquals(
            at(2026, 10, 13),
            RecurrenceAnchor.firstMatch("FREQ=MONTHLY;BYDAY=2TU", at(2026, 9, 12), stockholm)
        )
    }

    @Test
    fun monthlyByDayNegativeOrdinal_movesToLastWeekdayOfMonth() {
        assertEquals(
            at(2026, 9, 25),
            RecurrenceAnchor.firstMatch("FREQ=MONTHLY;BYDAY=-1FR", at(2026, 9, 12), stockholm)
        )
    }

    @Test
    fun yearlyByMonthAndMonthDay_movesToThatDateThisYear() {
        assertEquals(
            at(2026, 12, 25),
            RecurrenceAnchor.firstMatch(
                "FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25", at(2026, 9, 12), stockholm
            )
        )
    }

    // With no BYMONTHDAY the day-of-month is the anchor's, as DTSTART would
    // supply it — the 12th of December, not the 1st.
    @Test
    fun yearlyByMonthOnly_keepsAnchorsDayOfMonth() {
        assertEquals(
            at(2026, 12, 12),
            RecurrenceAnchor.firstMatch("FREQ=YEARLY;BYMONTH=12", at(2026, 9, 12), stockholm)
        )
    }

    @Test
    fun yearlyLeapDay_looksAheadToTheNextLeapYear() {
        assertEquals(
            at(2028, 2, 29),
            RecurrenceAnchor.firstMatch(
                "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29", at(2026, 3, 1), stockholm
            )
        )
    }

    // With BYMONTH, a BYDAY ordinal counts within the month (last Monday of
    // May), not within the year.
    @Test
    fun yearlyByMonthAndOrdinalByDay_countsWithinTheMonth() {
        assertEquals(
            at(2027, 5, 31),
            RecurrenceAnchor.firstMatch(
                "FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO", at(2026, 9, 12), stockholm
            )
        )
    }

    // "Last weekday of the month": BYSETPOS picks from the BYDAY set, so the
    // anchor is Wednesday 30 September, not the next weekday after the 12th.
    @Test
    fun monthlyBySetPos_selectsFromTheExpandedSet() {
        assertEquals(
            at(2026, 9, 30),
            RecurrenceAnchor.firstMatch(
                "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", at(2026, 9, 12), stockholm
            )
        )
    }

    // In a DAILY rule BYDAY only filters: Saturday the 12th skips to Monday.
    @Test
    fun dailyByDay_filtersToTheNextListedWeekday() {
        assertEquals(
            at(2026, 9, 14),
            RecurrenceAnchor.firstMatch("FREQ=DAILY;BYDAY=MO,WE", at(2026, 9, 12), stockholm)
        )
    }

    // An anchor the rule already generates is returned untouched, so a rule
    // change that keeps the day never moves the series.
    @Test
    fun anchorOnRule_isUnchanged() {
        val saturday = at(2026, 9, 12)
        assertEquals(
            saturday,
            RecurrenceAnchor.firstMatch("FREQ=WEEKLY;BYDAY=SA;COUNT=4", saturday, stockholm)
        )
    }

    // Rules with no day spec take it from the anchor, so they fit any anchor.
    @Test
    fun implicitRules_fitAnyAnchor() {
        val the31st = at(2026, 10, 31)
        assertEquals(the31st, RecurrenceAnchor.firstMatch("FREQ=MONTHLY", the31st, stockholm))
        assertEquals(the31st, RecurrenceAnchor.firstMatch("FREQ=WEEKLY", the31st, stockholm))
        assertEquals(the31st, RecurrenceAnchor.firstMatch("FREQ=YEARLY", the31st, stockholm))
    }

    // Stockholm falls back on 2026-10-25, so Sunday 10:00 is 25 hours after
    // Saturday 10:00 — the walk must keep the wall-clock time, not add 24h.
    @Test
    fun crossingDst_keepsWallClockTime() {
        assertEquals(
            at(2026, 10, 25),
            RecurrenceAnchor.firstMatch("FREQ=WEEKLY;BYDAY=SU", at(2026, 10, 24), stockholm)
        )
        assertEquals(
            25L * 3_600_000L,
            at(2026, 10, 25) - at(2026, 10, 24)
        )
    }

    @Test
    fun unsupportedRule_returnsNull() {
        assertEquals(null, RecurrenceAnchor.firstMatch("FREQ=HOURLY", at(2026, 9, 12), stockholm))
        assertEquals(null, RecurrenceAnchor.firstMatch("garbage", at(2026, 9, 12), stockholm))
    }

    // 30 February never comes, so the walk gives up rather than looping.
    @Test
    fun ruleThatNeverGenerates_returnsNull() {
        assertEquals(
            null,
            RecurrenceAnchor.firstMatch(
                "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30", at(2026, 9, 12), stockholm
            )
        )
    }
}
