package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * updateRecurring's day-move check, in [resolveSeriesTimes]: with no new
 * rule, the series' new start must be a day its kept rule generates (#189).
 * Timed series in UTC, so only the rule decides. Named after the Swift
 * `DayMoveConflictTests`, which it mirrors case for case — the platforms
 * must agree.
 *
 * The new start is the base (the series start) shifted by the move from the
 * reference occurrence to the target, so the cases where the two differ
 * check the start that is written, not just the target.
 */
internal class DayMoveConflictTest {
    private val utc = TimeZone.getTimeZone("UTC")

    /**
     * Moves the occurrence at [reference] of a timed UTC [rrule] series that
     * starts at [base] to [to], keeping the rule; the series' new start, or
     * the refusal.
     */
    private fun move(rrule: String, base: Long, to: Long, reference: Long = base) =
        resolveSeriesTimes(
            baseMillis = base,
            referenceMillis = reference,
            existingDurationMillis = 3_600_000L,
            targetStart = to,
            durationMinutes = null,
            ruleEdit = SeriesRuleEdit.Keep(rrule),
            timeZoneId = utc.id,
            isAllDay = false,
            storedZone = utc
        ).map { it.first }

    private fun at(month: Int, day: Int, hour: Int = 10) = instantAt(utc, 2026, month, day, hour)

    // Thu 26 Nov 2026 (4th Thursday) -> Thu 19 Nov (3rd): the weekday and
    // month hold, but the rule doesn't generate the 3rd Thursday.
    @Test
    fun resolveSeriesTimes_ordinalByDay_moveToAnotherOrdinal_refused() {
        move("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", at(11, 26), at(11, 19)).assertRefused()
    }

    // Fri 30 Oct 2026 (last Friday) -> Fri 23 Oct.
    @Test
    fun resolveSeriesTimes_negativeOrdinalByDay_moveOffTheLastWeekday_refused() {
        move("FREQ=MONTHLY;BYDAY=-1FR", at(10, 30), at(10, 23)).assertRefused()
    }

    // The last weekday of the month: Fri 30 Oct 2026 -> Fri 23 Oct.
    @Test
    fun resolveSeriesTimes_bySetPos_moveOffThePickedPosition_refused() {
        move("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", at(10, 30), at(10, 23))
            .assertRefused()
    }

    // Thu 26 Nov 2026 -> Thu 3 Dec: the weekday holds, BYMONTH=11 doesn't.
    @Test
    fun resolveSeriesTimes_byMonth_moveOutOfThePinnedMonth_refused() {
        move("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", at(11, 26), at(12, 3)).assertRefused()
    }

    // Fri 13 Nov 2026 -> Fri 20 Nov: the weekday holds, BYMONTHDAY=13 doesn't.
    @Test
    fun resolveSeriesTimes_byDayAndMonthDay_moveOffThePinnedDayOfMonth_refused() {
        move("FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13", at(11, 13), at(11, 20)).assertRefused()
    }

    @Test
    fun resolveSeriesTimes_ordinalByDay_timeOnlyMove_allowed() {
        val target = at(11, 26, hour = 15)
        assertEquals(
            target,
            move("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", at(11, 26), target).getOrThrow()
        )
    }

    // A rule that pins no day follows its anchor anywhere.
    @Test
    fun resolveSeriesTimes_implicitRule_dayMove_allowed() {
        val target = at(11, 19)
        assertEquals(target, move("FREQ=MONTHLY", at(11, 26), target).getOrThrow())
    }

    // Mon 2 Nov 2026 -> Wed 4 Nov: another day the rule lists.
    @Test
    fun resolveSeriesTimes_multiDayByDay_moveOntoAnotherListedDay_allowed() {
        val target = at(11, 4)
        assertEquals(target, move("FREQ=WEEKLY;BYDAY=MO,WE,FR", at(11, 2), target).getOrThrow())
    }

    // Mon 2 Nov 2026 -> Tue 3 Nov.
    @Test
    fun resolveSeriesTimes_multiDayByDay_moveOffTheList_refused() {
        move("FREQ=WEEKLY;BYDAY=MO,WE,FR", at(11, 2), at(11, 3)).assertRefused()
    }

    // The Wed 4 Nov occurrence of a series starting Mon 2 Nov moves to Fri 6
    // Nov: the start moves two days with it, onto Wed 4 Nov.
    @Test
    fun resolveSeriesTimes_multiDayByDay_laterOccurrenceMoveKeepsStartOnTheList_allowed() {
        assertEquals(
            at(11, 4),
            move(
                "FREQ=WEEKLY;BYDAY=MO,WE,FR", at(11, 2), at(11, 6), reference = at(11, 4)
            ).getOrThrow()
        )
    }

    // The Fri 6 Nov occurrence moves to Mon 9 Nov, a day the rule generates,
    // but the start moves three days with it, onto Thu 5 Nov, which it doesn't.
    @Test
    fun resolveSeriesTimes_multiDayByDay_laterOccurrenceMovePushesStartOffTheList_refused() {
        move(
            "FREQ=WEEKLY;BYDAY=MO,WE,FR", at(11, 2), at(11, 9), reference = at(11, 6)
        ).assertRefused()
    }

    // A series another app anchored off its rule, on Tue 3 Nov: retiming its
    // Wed 4 Nov occurrence keeps the start on that Tuesday, which isn't a
    // day move, so it isn't refused.
    @Test
    fun resolveSeriesTimes_multiDayByDay_timeOnlyMoveOfAnOffRuleStart_allowed() {
        assertEquals(
            at(11, 3, hour = 15),
            move(
                "FREQ=WEEKLY;BYDAY=MO,WE,FR", at(11, 3), at(11, 4, hour = 15),
                reference = at(11, 4)
            ).getOrThrow()
        )
    }

    // A series another app anchored off its rule, on Tue 3 Nov: retiming
    // that first occurrence on the same Tuesday isn't a day move, so it isn't
    // refused, though the rule doesn't generate the day.
    @Test
    fun resolveSeriesTimes_multiDayByDay_timeOnlyMoveOfAnOffRuleFirstOccurrence_allowed() {
        val target = at(11, 3, hour = 15)
        assertEquals(target, move("FREQ=WEEKLY;BYDAY=MO,WE,FR", at(11, 3), target).getOrThrow())
    }

    // The Thu 26 Nov occurrence (4th Thursday) of a series starting Thu 22
    // Oct moves to Thu 24 Dec (also a 4th Thursday), but the start moves 28
    // days with it, onto Thu 19 Nov, the 3rd.
    @Test
    fun resolveSeriesTimes_ordinalByDay_laterOccurrenceMovePushesStartOffTheOrdinal_refused() {
        move(
            "FREQ=MONTHLY;BYDAY=4TH", at(10, 22), at(12, 24), reference = at(11, 26)
        ).assertRefused()
    }
}
