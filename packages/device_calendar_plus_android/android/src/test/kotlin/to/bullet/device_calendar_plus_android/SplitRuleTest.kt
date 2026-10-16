package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * [splitSeriesRule]: the rule a `thisAndFollowing` split that replaces the
 * rule gives the new series. EventKit counts a new rule's COUNT from the
 * original series' start, so the new series loses the occurrences the new
 * rule would have had before the split, and doesn't recur at all when that
 * leaves none (#124). The expected counts are what an iOS simulator saves
 * for the same splits of a daily series (at its fifth occurrence unless a
 * case names another day).
 */
internal class SplitRuleTest {
    private val utc = TimeZone.getTimeZone("UTC")

    // A Thursday, and the series' fifth daily occurrence four days on.
    private val seriesStart = instantAt(utc, 2026, 10, 15, 10)
    private val fifth = instantAt(utc, 2026, 10, 19, 10)

    private fun split(rule: String, at: Long = fifth) =
        splitSeriesRule(rule, seriesStart = seriesStart, splitAt = at, tz = utc)

    /** The series' occurrence [days] after its start. */
    private fun day(days: Int) = seriesStart + days * AllDayDates.MILLIS_PER_DAY

    @Test
    fun splitSeriesRule_dailyCount_dropsTheDaysBeforeTheSplit() {
        assertEquals("FREQ=DAILY;COUNT=16", split("FREQ=DAILY;COUNT=20"))
    }

    @Test
    fun splitSeriesRule_dailyCountAtTheSecondOccurrence_dropsOne() {
        assertEquals(
            "FREQ=DAILY;COUNT=4",
            split("FREQ=DAILY;COUNT=5", at = instantAt(utc, 2026, 10, 16, 10))
        )
    }

    // Every other day from the start: the 15th and 17th come before the split.
    @Test
    fun splitSeriesRule_dailyWithInterval_dropsOnlyTheDaysInPhase() {
        assertEquals("FREQ=DAILY;INTERVAL=2;COUNT=3", split("FREQ=DAILY;INTERVAL=2;COUNT=5"))
    }

    // On the start's weekday: only the start itself comes before the split.
    @Test
    fun splitSeriesRule_weeklyCount_dropsTheStartsWeek() {
        assertEquals("FREQ=WEEKLY;COUNT=9", split("FREQ=WEEKLY;COUNT=10"))
        assertEquals("FREQ=WEEKLY;COUNT=2", split("FREQ=WEEKLY;COUNT=3"))
    }

    // The series' start counts as the first occurrence even on a day the
    // new rule doesn't generate, as RFC 5545 counts DTSTART: Mondays from a
    // Thursday start have none before the split, yet still lose one.
    @Test
    fun splitSeriesRule_startOffTheNewRule_stillCountsTheStart() {
        assertEquals(
            "FREQ=WEEKLY;BYDAY=MO;COUNT=2",
            split("FREQ=WEEKLY;BYDAY=MO;COUNT=3")
        )
        // Saturday and Sunday, plus the Thursday start.
        assertEquals(
            "FREQ=WEEKLY;BYDAY=SA,SU;COUNT=2",
            split("FREQ=WEEKLY;BYDAY=SA,SU;COUNT=5")
        )
    }

    @Test
    fun splitSeriesRule_countUsedUpBeforeTheSplit_doesNotRecur() {
        assertNull(split("FREQ=DAILY;COUNT=4"))
        assertNull(split("FREQ=DAILY;COUNT=3"))
    }

    @Test
    fun splitSeriesRule_noCount_isUnchanged() {
        assertEquals("FREQ=DAILY", split("FREQ=DAILY"))
        assertEquals(
            "FREQ=DAILY;UNTIL=20261231T000000Z",
            split("FREQ=DAILY;UNTIL=20261231T000000Z")
        )
    }

    // Every other week, counted in weeks from Monday: the start's week (the
    // Thursday 15th and Sunday 18th) is in phase, the next isn't, so a split
    // on Friday the 23rd drops two. Weeks from Sunday would put the 18th in
    // the off week.
    @Test
    fun splitSeriesRule_weeklyWithInterval_countsTheWeeksFromMonday() {
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;COUNT=8",
            split("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;COUNT=10", at = day(8))
        )
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;WKST=MO;COUNT=8",
            split("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;WKST=MO;COUNT=10", at = day(8))
        )
    }

    // Split three weeks in: the start and the 29th, two weeks on, come
    // before it; the 22nd is in the off week.
    @Test
    fun splitSeriesRule_weeklyWithInterval_dropsOnlyTheWeeksInPhase() {
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;COUNT=8",
            split("FREQ=WEEKLY;INTERVAL=2;COUNT=10", at = day(21))
        )
        // Monday the 26th is the split itself, so only the start comes before.
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;COUNT=9",
            split("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;COUNT=10", at = day(11))
        )
    }

    // Split on 16 December: 15 October, November and December come before.
    @Test
    fun splitSeriesRule_monthlyCount_dropsTheMonthsBeforeTheSplit() {
        assertEquals("FREQ=MONTHLY;COUNT=3", split("FREQ=MONTHLY;COUNT=6", at = day(62)))
    }

    // Every other month: November is out of phase.
    @Test
    fun splitSeriesRule_monthlyWithInterval_dropsOnlyTheMonthsInPhase() {
        assertEquals(
            "FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=15;COUNT=4",
            split("FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=15;COUNT=6", at = day(62))
        )
    }

    // Split on 24 November: the start and 2 November, its first Monday.
    @Test
    fun splitSeriesRule_monthlyByDayOrdinal_dropsTheStartAndTheOrdinalDays() {
        assertEquals(
            "FREQ=MONTHLY;BYDAY=1MO;COUNT=4",
            split("FREQ=MONTHLY;BYDAY=1MO;COUNT=6", at = day(40))
        )
    }

    // Split on 16 October 2027: the start and its first anniversary.
    @Test
    fun splitSeriesRule_yearlyCount_dropsTheYearsBeforeTheSplit() {
        assertEquals("FREQ=YEARLY;COUNT=3", split("FREQ=YEARLY;COUNT=5", at = day(366)))
        // Every other year: only the start.
        assertEquals(
            "FREQ=YEARLY;INTERVAL=2;COUNT=4",
            split("FREQ=YEARLY;INTERVAL=2;COUNT=5", at = day(366))
        )
    }

    // A Los Angeles series at 10:00 from Thursday 29 October, split on 3
    // November after the clocks go back on the 1st. The days are stepped at
    // the wall-clock 10:00, so the split day's own 10:00 PST is the split
    // and not before it: five days, not the six that 24-hour steps (landing
    // at 09:00 PST) would count.
    @Test
    fun splitSeriesRule_dailyAcrossDst_countsTheLocalDays() {
        val la = TimeZone.getTimeZone("America/Los_Angeles")
        assertEquals(
            "FREQ=DAILY;COUNT=5",
            splitSeriesRule(
                "FREQ=DAILY;COUNT=10",
                seriesStart = instantAt(la, 2026, 10, 29, 10),
                splitAt = instantAt(la, 2026, 11, 3, 10),
                tz = la
            )
        )
    }

    // Split at the series' own start, the count is left as it is.
    @Test
    fun splitSeriesRule_atTheSeriesStart_keepsTheCount() {
        assertEquals("FREQ=DAILY;COUNT=5", split("FREQ=DAILY;COUNT=5", at = seriesStart))
    }

    // A rule outside the modelled subset (a FREQ it doesn't know) can't be
    // expanded, so it is left exactly as given.
    @Test
    fun splitSeriesRule_ruleOutsideTheModelledSubset_isUnchanged() {
        assertEquals("FREQ=HOURLY;COUNT=5;INTERVAL=2", split("FREQ=HOURLY;COUNT=5;INTERVAL=2"))
    }
}
