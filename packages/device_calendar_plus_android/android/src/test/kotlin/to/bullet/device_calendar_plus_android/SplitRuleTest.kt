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
 * for the same splits of a daily series at its fifth occurrence.
 */
internal class SplitRuleTest {
    private val utc = TimeZone.getTimeZone("UTC")

    // A Thursday, and the series' fifth daily occurrence four days on.
    private val seriesStart = instantAt(utc, 2026, 10, 15, 10)
    private val fifth = instantAt(utc, 2026, 10, 19, 10)

    private fun split(rule: String, at: Long = fifth) =
        splitSeriesRule(rule, seriesStart = seriesStart, splitAt = at, tz = utc)

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
}
