package to.bullet.device_calendar_plus_android

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

    private fun at(year: Int, month: Int, day: Int, hour: Int = 10): Long =
        instantAt(stockholm, year, month, day, hour)

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

    // Per RFC 5545 BYDAY limits a BYMONTHDAY set rather than expanding it:
    // "Friday the 13th" skips October's Tuesday 13th for November's Friday.
    @Test
    fun monthlyByMonthDayAndByDay_byDayLimitsTheSet() {
        assertEquals(
            at(2026, 11, 13),
            RecurrenceAnchor.firstMatch(
                "FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR", at(2026, 9, 12), stockholm
            )
        )
    }

    // "First weekday of the month": a positive BYSETPOS counts from the start
    // of the BYDAY set, so the anchor is Thursday 1 October.
    @Test
    fun monthlyBySetPosPositive_selectsFromTheStartOfTheSet() {
        assertEquals(
            at(2026, 10, 1),
            RecurrenceAnchor.firstMatch(
                "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1", at(2026, 9, 12), stockholm
            )
        )
    }

    // RFC 5545 allows an explicit "+" on a BYDAY ordinal; iOS never sees the
    // string form, so this case has no Swift mirror.
    @Test
    fun byDayWithPlusPrefix_parsesAsAPositiveOrdinal() {
        assertEquals(
            at(2026, 10, 5),
            RecurrenceAnchor.firstMatch("FREQ=MONTHLY;BYDAY=+1MO", at(2026, 9, 12), stockholm)
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

    // With no BYMONTH the month is the anchor's, as DTSTART would supply it
    // (RFC 5545 would expand across every month): the 15th of September is
    // past, so the anchor is next September's, not 15 October.
    @Test
    fun yearlyByMonthDayOnly_keepsAnchorsMonth() {
        assertEquals(
            at(2027, 9, 15),
            RecurrenceAnchor.firstMatch("FREQ=YEARLY;BYMONTHDAY=15", at(2026, 9, 20), stockholm)
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

    // BYDAY alone on a yearly rule counts within the year: 2026's second
    // Monday (12 January) is past, so the anchor is 2027's (11 January).
    @Test
    fun yearlyByDayOnly_ordinalCountsWithinTheYear() {
        assertEquals(
            at(2027, 1, 11),
            RecurrenceAnchor.firstMatch("FREQ=YEARLY;BYDAY=2MO", at(2026, 9, 12), stockholm)
        )
    }

    // "Last weekday of January": BYSETPOS picks from the year's set, which
    // BYMONTH narrows to January's weekdays — Friday 29 January 2027.
    @Test
    fun yearlyBySetPos_selectsFromTheYearsSet() {
        assertEquals(
            at(2027, 1, 29),
            RecurrenceAnchor.firstMatch(
                "FREQ=YEARLY;BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", at(2026, 9, 12), stockholm
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

    // A rule outside the modelled subset is assumed to fit its anchor — not
    // refused as one that generates nothing.
    @Test
    fun unsupportedRule_leavesTheAnchorAlone() {
        val anchor = at(2026, 9, 12)
        assertEquals(anchor, RecurrenceAnchor.firstMatch("FREQ=HOURLY", anchor, stockholm))
        assertEquals(anchor, RecurrenceAnchor.firstMatch("garbage", anchor, stockholm))
    }

    // 30 February never comes, so the walk gives up rather than looping —
    // and the caller refuses the rule instead of anchoring off it.
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
