package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * [keptRuleAfterSplit] and [replacedRuleAfterSplit]: the rule a
 * `thisAndFollowing` split gives the new series.
 *
 * Keep: a kept rule's COUNT drops by the occurrences the rule generates
 * before the split, deleted ones included (#220), and keeps at least one;
 * the provider's count is only the fallback for a rule that can't be
 * expanded. The deleted-occurrences case matches what an iOS simulator saves
 * (COUNT=6). The BYHOUR, daily/weekly BYSETPOS fallback, monthly/yearly
 * BYSETPOS, count-used-up and no-COUNT cases pin Android-only behaviour and
 * aren't from EventKit.
 *
 * Replace: EventKit counts a new rule's COUNT from the original series'
 * start, so the new series loses the occurrences the new rule would have had
 * before the split, and doesn't recur at all when that leaves none (#124).
 * The plain daily, weekly, monthly and yearly counts are what an iOS
 * simulator saves for the same splits of a daily series (at its fifth
 * occurrence unless a case names another day). The DST, WKST=SU, BYSETPOS,
 * out-of-subset and no-COUNT cases pin Android-only behaviour and aren't
 * from EventKit.
 */
internal class SplitRuleTest {
    private val utc = TimeZone.getTimeZone("UTC")

    // A Thursday, and the series' fifth daily occurrence four days on.
    private val seriesStart = instantAt(utc, 2026, 10, 15, 10)
    private val fifth = instantAt(utc, 2026, 10, 19, 10)

    private fun split(rule: String, at: Long = fifth) =
        replacedRuleAfterSplit(rule, seriesStart = seriesStart, splitAt = at, tz = utc)

    private fun keep(
        rule: String,
        at: Long = fifth,
        providerCountBefore: () -> Int = { error("a countable rule needs no provider count") },
    ) = keptRuleAfterSplit(
        rule,
        seriesStart = seriesStart,
        splitAt = at,
        tz = utc,
        providerCountBefore = providerCountBefore
    )

    /** The series' occurrence [days] after its start. */
    private fun day(days: Int) = seriesStart + days * AllDayDates.MILLIS_PER_DAY

    @Test
    fun replacedRuleAfterSplit_dailyCount_dropsTheDaysBeforeTheSplit() {
        assertEquals("FREQ=DAILY;COUNT=16", split("FREQ=DAILY;COUNT=20"))
    }

    @Test
    fun replacedRuleAfterSplit_dailyCountAtTheSecondOccurrence_dropsOne() {
        assertEquals(
            "FREQ=DAILY;COUNT=4",
            split("FREQ=DAILY;COUNT=5", at = instantAt(utc, 2026, 10, 16, 10))
        )
    }

    // Every other day from the start: the 15th and 17th come before the split.
    @Test
    fun replacedRuleAfterSplit_dailyWithInterval_dropsOnlyTheDaysInPhase() {
        assertEquals("FREQ=DAILY;INTERVAL=2;COUNT=3", split("FREQ=DAILY;INTERVAL=2;COUNT=5"))
    }

    // On the start's weekday: only the start itself comes before the split.
    @Test
    fun replacedRuleAfterSplit_weeklyCount_dropsTheStartsWeek() {
        assertEquals("FREQ=WEEKLY;COUNT=9", split("FREQ=WEEKLY;COUNT=10"))
        assertEquals("FREQ=WEEKLY;COUNT=2", split("FREQ=WEEKLY;COUNT=3"))
    }

    // The series' start counts as the first occurrence even on a day the
    // new rule doesn't generate, as RFC 5545 counts DTSTART: Mondays from a
    // Thursday start have none before the split, yet still lose one.
    @Test
    fun replacedRuleAfterSplit_startOffTheNewRule_stillCountsTheStart() {
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
    fun replacedRuleAfterSplit_countUsedUpBeforeTheSplit_doesNotRecur() {
        assertNull(split("FREQ=DAILY;COUNT=4"))
        assertNull(split("FREQ=DAILY;COUNT=3"))
    }

    @Test
    fun replacedRuleAfterSplit_noCount_isUnchanged() {
        assertEquals("FREQ=DAILY", split("FREQ=DAILY"))
        assertEquals(
            "FREQ=DAILY;UNTIL=20261231T000000Z",
            split("FREQ=DAILY;UNTIL=20261231T000000Z")
        )
    }

    // Every other week, counted in weeks from Monday: the start's week (the
    // Thursday 15th and Sunday 18th) is in phase, the next isn't, so a split
    // on Friday the 23rd drops two.
    @Test
    fun replacedRuleAfterSplit_weeklyWithInterval_countsTheWeeksFromMonday() {
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;COUNT=8",
            split("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;COUNT=10", at = day(8))
        )
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;WKST=MO;COUNT=8",
            split("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;WKST=MO;COUNT=10", at = day(8))
        )
    }

    // The same split with weeks from Sunday: the 18th starts the off week,
    // with the 22nd, so only the start comes before the split. RFC 5545's
    // count; not checked against EventKit.
    @Test
    fun replacedRuleAfterSplit_weeklyWithIntervalFromSunday_countsTheWeeksFromSunday() {
        assertEquals(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;WKST=SU;COUNT=9",
            split("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,TH;WKST=SU;COUNT=10", at = day(8))
        )
    }

    // Split three weeks in: the start and the 29th, two weeks on, come
    // before it; the 22nd is in the off week.
    @Test
    fun replacedRuleAfterSplit_weeklyWithInterval_dropsOnlyTheWeeksInPhase() {
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
    fun replacedRuleAfterSplit_monthlyCount_dropsTheMonthsBeforeTheSplit() {
        assertEquals("FREQ=MONTHLY;COUNT=3", split("FREQ=MONTHLY;COUNT=6", at = day(62)))
    }

    // Every other month: November is out of phase.
    @Test
    fun replacedRuleAfterSplit_monthlyWithInterval_dropsOnlyTheMonthsInPhase() {
        assertEquals(
            "FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=15;COUNT=4",
            split("FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=15;COUNT=6", at = day(62))
        )
    }

    // Split on 24 November: the start and 2 November, its first Monday.
    @Test
    fun replacedRuleAfterSplit_monthlyByDayOrdinal_dropsTheStartAndTheOrdinalDays() {
        assertEquals(
            "FREQ=MONTHLY;BYDAY=1MO;COUNT=4",
            split("FREQ=MONTHLY;BYDAY=1MO;COUNT=6", at = day(40))
        )
    }

    // Split on 16 October 2027: the start and its first anniversary.
    @Test
    fun replacedRuleAfterSplit_yearlyCount_dropsTheYearsBeforeTheSplit() {
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
    fun replacedRuleAfterSplit_dailyAcrossDst_countsTheLocalDays() {
        val la = TimeZone.getTimeZone("America/Los_Angeles")
        assertEquals(
            "FREQ=DAILY;COUNT=5",
            replacedRuleAfterSplit(
                "FREQ=DAILY;COUNT=10",
                seriesStart = instantAt(la, 2026, 10, 29, 10),
                splitAt = instantAt(la, 2026, 11, 3, 10),
                tz = la
            )
        )
    }

    // Split at the series' own start, the count is left as it is.
    @Test
    fun replacedRuleAfterSplit_atTheSeriesStart_keepsTheCount() {
        assertEquals("FREQ=DAILY;COUNT=5", split("FREQ=DAILY;COUNT=5", at = seriesStart))
    }

    // A rule outside the modelled subset (a FREQ it doesn't know) can't be
    // expanded, so it is left exactly as given.
    @Test
    fun replacedRuleAfterSplit_ruleOutsideTheModelledSubset_isUnchanged() {
        assertEquals("FREQ=HOURLY;COUNT=5;INTERVAL=2", split("FREQ=HOURLY;COUNT=5;INTERVAL=2"))
    }

    // A BYSETPOS on a daily rule is outside what the rule count models, so
    // the rule can't be counted and its COUNT is left as given.
    @Test
    fun replacedRuleAfterSplit_dailyBySetPos_isUnchanged() {
        assertEquals(
            "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=10",
            split("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=10")
        )
    }

    // A monthly BYSETPOS is modelled. Split on 16 December: the start and
    // the last weekdays of October and November (the 30th of each) come
    // before it.
    @Test
    fun replacedRuleAfterSplit_monthlyBySetPos_dropsTheMonthsBeforeTheSplit() {
        assertEquals(
            "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3",
            split("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=6", at = day(62))
        )
    }

    // Two of the four occurrences before the split were deleted, so the
    // provider's Instances (which leave EXDATE'd and cancelled occurrences
    // out) list only two. COUNT counts them anyway (RFC 5545), and an iOS
    // simulator saves the new series with COUNT=6 for this split all the
    // same; the provider's two gave it eight, running past the original's
    // end (#220).
    @Test
    fun keptRuleAfterSplit_deletedOccurrencesBeforeTheSplit_stillCountsThem() {
        assertEquals(
            "FREQ=DAILY;COUNT=6",
            keep("FREQ=DAILY;COUNT=10", providerCountBefore = { 2 })
        )
    }

    // A kept rule can come from another app, with parts the rule count
    // doesn't model: here two occurrences a day, eight before the split.
    // Counting it as one a day would leave the new series six, not two, so
    // the provider's count is used instead.
    @Test
    fun keptRuleAfterSplit_aPartTheCountDoesNotModel_usesTheProviderCount() {
        assertEquals(
            "FREQ=DAILY;BYHOUR=10,14;COUNT=2",
            keep("FREQ=DAILY;BYHOUR=10,14;COUNT=10", providerCountBefore = { 8 })
        )
    }

    // A BYSETPOS on a daily or weekly rule is outside what the rule count
    // models, so the provider's count is used rather than counting the rule
    // as a plain daily or weekly one.
    @Test
    fun keptRuleAfterSplit_weeklyBySetPos_usesTheProviderCount() {
        assertEquals(
            "FREQ=WEEKLY;BYDAY=MO,TU,WE;BYSETPOS=1;COUNT=7",
            keep("FREQ=WEEKLY;BYDAY=MO,TU,WE;BYSETPOS=1;COUNT=10", providerCountBefore = { 3 })
        )
    }

    @Test
    fun keptRuleAfterSplit_dailyBySetPos_usesTheProviderCount() {
        assertEquals(
            "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=7",
            keep("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=10", providerCountBefore = { 3 })
        )
    }

    // A monthly or yearly BYSETPOS is modelled, so a kept one is counted
    // from the rule, without asking the provider: the start and the last
    // weekdays of October and November come before a split on 16 December.
    @Test
    fun keptRuleAfterSplit_monthlyBySetPos_countsTheRule() {
        assertEquals(
            "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3",
            keep("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=6", at = day(62))
        )
    }

    // The last weekday of each October: a split on 16 October 2027 has the
    // start and 30 October 2026 before it.
    @Test
    fun keptRuleAfterSplit_yearlyBySetPos_countsTheRule() {
        assertEquals(
            "FREQ=YEARLY;BYMONTH=10;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=4",
            keep("FREQ=YEARLY;BYMONTH=10;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=6", at = day(366))
        )
    }

    // Unlike a replacing rule, a kept one always leaves the split's own
    // occurrence: it is one of the series' own.
    @Test
    fun keptRuleAfterSplit_countUsedUp_keepsOne() {
        assertEquals("FREQ=DAILY;COUNT=1", keep("FREQ=DAILY;COUNT=3"))
    }

    @Test
    fun keptRuleAfterSplit_noCount_isUnchanged() {
        assertEquals(
            "FREQ=DAILY",
            keep("FREQ=DAILY", providerCountBefore = { error("a rule without COUNT needs no count") })
        )
    }
}
