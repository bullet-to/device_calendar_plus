package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

/**
 * updateRecurring's `start` pre-flight, [resolveTargetStart], on devices
 * either side of UTC (#144). A stored all-day occurrence is UTC midnight; the
 * caller's new start arrives from Dart as the device-local midnight of the
 * day it means, and must be brought into the stored frame before the
 * day-move check reads it and the anchor shift uses it. 2026-06-06 is a
 * Saturday.
 */
internal class ResolveTargetStartTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val la = TimeZone.getTimeZone("America/Los_Angeles")
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")

    /** The June [day]'s all-day occurrence, as the provider stores it. */
    private fun stored(day: Int) = instantAt(utc, 2026, 6, day)

    /**
     * Resolves [newStart] against the stored [reference] start of a
     * [rrule] series on a device in [zone]. [rowAllDay] is the row's frame
     * before the edit, [effectiveIsAllDay] after it.
     */
    private fun resolve(
        newStart: Long,
        reference: Long,
        rowAllDay: Boolean = true,
        effectiveIsAllDay: Boolean = true,
        rrule: String = "FREQ=WEEKLY;BYDAY=SA",
        zone: TimeZone = la,
        changingRule: Boolean = false
    ) = resolveTargetStart(
        newStartMillis = newStart,
        rowRrule = rrule,
        rowAllDay = rowAllDay,
        rowTimeZone = zone.id,
        referenceMillis = reference,
        effectiveIsAllDay = effectiveIsAllDay,
        changingRule = changingRule,
        deviceZone = zone
    )

    /**
     * Moves an all-day [rrule] series stored on June [storedDay] to the
     * local midnight of June [newDay], from a device in [zone].
     */
    private fun moveAllDay(rrule: String, storedDay: Int, newDay: Int, zone: TimeZone) =
        resolve(instantAt(zone, 2026, 6, newDay), stored(storedDay), rrule = rrule, zone = zone)

    private fun Result<Long?>.failureCode() =
        assertIs<CalendarException>(
            exceptionOrNull(),
            "expected a refusal, got ${getOrNull()}"
        ).code

    // West of UTC the stored UTC midnight is the previous local evening:
    // read in the device zone it looked like a Friday, so keeping the
    // Saturday was refused and moving to the Friday let through.
    @Test
    fun resolveTargetStart_allDaySameDayWestOfUtc_returnsStoredMidnight() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, 6, la)
        assertEquals(stored(6), result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayDayEarlierWestOfUtc_refused() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, 5, la)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    @Test
    fun resolveTargetStart_allDayMonthDayMoveWestOfUtc_refused() {
        val result = moveAllDay("FREQ=MONTHLY;BYMONTHDAY=6", 6, 5, la)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    @Test
    fun resolveTargetStart_allDaySameDayEastOfUtc_returnsStoredMidnight() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, 6, sydney)
        assertEquals(stored(6), result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayDayLaterEastOfUtc_refused() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, 7, sydney)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    // East of UTC a local midnight is the previous UTC day: passed on
    // unconverted, a one-day move counted zero days and left the series put.
    @Test
    fun resolveTargetStart_allDayDayLaterEastOfUtcImplicitRule_returnsNextStoredMidnight() {
        val result = moveAllDay("FREQ=DAILY;COUNT=4", 6, 7, sydney)
        assertEquals(stored(7), result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayDayLaterWestOfUtcImplicitRule_returnsNextStoredMidnight() {
        val result = moveAllDay("FREQ=DAILY;COUNT=4", 6, 7, la)
        assertEquals(stored(7), result.getOrThrow())
    }

    // The same edit toggles all-day off: the stored start is read in UTC,
    // the new timed start in the row's zone.
    @Test
    fun resolveTargetStart_allDayToTimedSameDay_returnsTimedStart() {
        val newStart = instantAt(la, 2026, 6, 6, 9)
        val result = resolve(newStart, stored(6), effectiveIsAllDay = false)
        assertEquals(newStart, result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayToTimedDayEarlier_refused() {
        val result = resolve(instantAt(la, 2026, 6, 5, 9), stored(6), effectiveIsAllDay = false)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    // The same edit toggles all-day on: Saturday 20:00 Los Angeles is Sunday
    // in UTC, so reading both instants in one zone would refuse a same-day
    // move.
    @Test
    fun resolveTargetStart_timedToAllDaySameDay_returnsStoredMidnight() {
        val result = resolve(
            instantAt(la, 2026, 6, 6),
            instantAt(la, 2026, 6, 6, 20),
            rowAllDay = false
        )
        assertEquals(stored(6), result.getOrThrow())
    }

    // A new rule lifts the day-move check, but the start still reaches the
    // #140 re-anchor in the stored frame: east of UTC the raw local midnight
    // is the previous UTC day.
    @Test
    fun resolveTargetStart_allDayDayMoveWithNewRule_returnsStoredMidnight() {
        val result = resolve(
            instantAt(sydney, 2026, 6, 7),
            stored(6),
            zone = sydney,
            changingRule = true
        )
        assertEquals(stored(7), result.getOrThrow())
    }
}
