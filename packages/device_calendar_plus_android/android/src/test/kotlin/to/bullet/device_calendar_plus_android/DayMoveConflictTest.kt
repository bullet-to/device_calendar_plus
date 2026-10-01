package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

/**
 * updateRecurring's day-move check, through [resolveTargetStart]: a start
 * move with no new rule is refused unless the existing rule generates the
 * target's day (#189). Timed series in UTC, so only the rule decides. Mirrors
 * the Swift `DayMoveConflictTests` case for case — the platforms must agree.
 */
internal class DayMoveConflictTest {
    private val utc = TimeZone.getTimeZone("UTC")

    /**
     * Moves a timed UTC [rrule] series to [to], keeping the rule. Only the
     * target is passed: the check doesn't read where the move starts from.
     */
    private fun move(rrule: String, to: Long) = resolveTargetStart(
        newStartMillis = to,
        rowRrule = rrule,
        rowTimeZone = utc.id,
        effectiveIsAllDay = false,
        changingRule = false,
        deviceZone = utc
    )

    private fun at(month: Int, day: Int, hour: Int = 10) = instantAt(utc, 2026, month, day, hour)

    private fun Result<Long?>.assertRefused() =
        assertEquals(
            PlatformExceptionCodes.INVALID_ARGUMENTS,
            assertIs<CalendarException>(
                exceptionOrNull(),
                "expected a refusal, got ${getOrNull()}"
            ).code
        )

    // Thu 26 Nov 2026 (4th Thursday) -> Thu 19 Nov (3rd): the weekday and
    // month hold, but the rule doesn't generate the 3rd Thursday.
    @Test
    fun ordinalByDay_moveToAnotherOrdinal_refused() {
        move("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", at(11, 19)).assertRefused()
    }

    // Fri 30 Oct 2026 (last Friday) -> Fri 23 Oct.
    @Test
    fun negativeOrdinalByDay_moveOffTheLastWeekday_refused() {
        move("FREQ=MONTHLY;BYDAY=-1FR", at(10, 23)).assertRefused()
    }

    // The last weekday of the month: Fri 30 Oct 2026 -> Fri 23 Oct.
    @Test
    fun bySetPos_moveOffThePickedPosition_refused() {
        move("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", at(10, 23)).assertRefused()
    }

    // Thu 26 Nov 2026 -> Thu 3 Dec: the weekday holds, BYMONTH=11 doesn't.
    @Test
    fun byMonth_moveOutOfThePinnedMonth_refused() {
        move("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", at(12, 3)).assertRefused()
    }

    // Fri 13 Nov 2026 -> Fri 20 Nov: the weekday holds, BYMONTHDAY=13 doesn't.
    @Test
    fun byDayAndMonthDay_moveOffThePinnedDayOfMonth_refused() {
        move("FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13", at(11, 20)).assertRefused()
    }

    @Test
    fun ordinalByDay_timeOnlyMove_allowed() {
        val target = at(11, 26, hour = 15)
        assertEquals(
            target,
            move("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", target).getOrThrow()
        )
    }

    // A rule that pins no day follows its anchor anywhere.
    @Test
    fun implicitRule_dayMove_allowed() {
        val target = at(11, 19)
        assertEquals(target, move("FREQ=MONTHLY", target).getOrThrow())
    }
}
