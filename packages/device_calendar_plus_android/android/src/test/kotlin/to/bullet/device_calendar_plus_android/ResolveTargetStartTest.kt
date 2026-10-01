package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * updateRecurring's `start` pre-flight, [resolveTargetStart], on devices
 * either side of UTC (#144). A stored all-day occurrence is UTC midnight; the
 * caller's new start arrives from Dart as the device-local midnight of the
 * day it means, and must be brought into the stored frame before the anchor
 * shift uses it and the day-move check reads the start it produces. Each
 * case runs the start on through [resolveSeriesTimes], as an allEvents edit
 * does, and reads back the series' new start. 2026-06-06 is a Saturday.
 */
internal class ResolveTargetStartTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val la = TimeZone.getTimeZone("America/Los_Angeles")
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")

    /** The June [day]'s all-day occurrence, as the provider stores it. */
    private fun stored(day: Int) = instantAt(utc, 2026, 6, day)

    /**
     * Moves a [rrule] series stored at [base] to [newStart] from a device in
     * [zone], and returns the series' new start. [effectiveIsAllDay] is the
     * series' frame after the edit. A [newRule] replaces [rrule], lifting the
     * day-move check.
     */
    private fun resolve(
        newStart: Long,
        effectiveIsAllDay: Boolean = true,
        rrule: String = "FREQ=WEEKLY;BYDAY=SA",
        zone: TimeZone = la,
        base: Long = stored(6),
        newRule: String? = null
    ): Result<Long> = resolveSeriesTimes(
        baseMillis = base,
        referenceMillis = base,
        existingDurationMillis = 3_600_000L,
        targetStart = resolveTargetStart(
            newStartMillis = newStart,
            effectiveIsAllDay = effectiveIsAllDay,
            deviceZone = zone
        ),
        durationMinutes = null,
        rrule = newRule,
        timeZoneId = zone.id,
        isAllDay = effectiveIsAllDay,
        keptRule = if (newRule == null) rrule else null
    ).map { it.first }

    /**
     * Moves an all-day [rrule] series stored on Saturday 6 June to the local
     * midnight of June [newDay], from a device in [zone].
     */
    private fun moveAllDay(rrule: String, newDay: Int, zone: TimeZone) =
        resolve(instantAt(zone, 2026, 6, newDay), rrule = rrule, zone = zone)

    // West of UTC the stored UTC midnight is the previous local evening:
    // read in the device zone it looked like a Friday, so keeping the
    // Saturday was refused and moving to the Friday let through.
    @Test
    fun resolveTargetStart_allDaySameDayWestOfUtc_returnsStoredMidnight() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, la)
        assertEquals(stored(6), result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayDayEarlierWestOfUtc_refused() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 5, la)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    @Test
    fun resolveTargetStart_allDayMonthDayMoveWestOfUtc_refused() {
        val result = moveAllDay("FREQ=MONTHLY;BYMONTHDAY=6", 5, la)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    @Test
    fun resolveTargetStart_allDaySameDayEastOfUtc_returnsStoredMidnight() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, sydney)
        assertEquals(stored(6), result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayDayLaterEastOfUtc_refused() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 7, sydney)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    // East of UTC a local midnight is the previous UTC day: passed on
    // unconverted, a one-day move counted zero days and left the series put.
    @Test
    fun resolveTargetStart_allDayDayLaterEastOfUtcImplicitRule_returnsNextStoredMidnight() {
        val result = moveAllDay("FREQ=DAILY;COUNT=4", 7, sydney)
        assertEquals(stored(7), result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayDayLaterWestOfUtcImplicitRule_returnsNextStoredMidnight() {
        val result = moveAllDay("FREQ=DAILY;COUNT=4", 7, la)
        assertEquals(stored(7), result.getOrThrow())
    }

    // The same edit toggles all-day off: the new timed start is read in the
    // row's zone, not the UTC of the stored all-day start.
    @Test
    fun resolveTargetStart_allDayToTimedSameDay_returnsTimedStart() {
        val newStart = instantAt(la, 2026, 6, 6, 9)
        val result = resolve(newStart, effectiveIsAllDay = false)
        assertEquals(newStart, result.getOrThrow())
    }

    @Test
    fun resolveTargetStart_allDayToTimedDayEarlier_refused() {
        val result = resolve(instantAt(la, 2026, 6, 5, 9), effectiveIsAllDay = false)
        assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, result.failureCode())
    }

    // The same edit toggles a Saturday 20:00 Los Angeles series (Sunday in
    // UTC) all-day: its local Saturday midnight becomes Saturday's UTC
    // midnight, which the rule generates.
    @Test
    fun resolveTargetStart_timedToAllDaySameDay_returnsStoredMidnight() {
        val result = resolve(instantAt(la, 2026, 6, 6), base = instantAt(la, 2026, 6, 6, 20))
        assertEquals(stored(6), result.getOrThrow())
    }

    // A new rule lifts the day-move check, but the start still reaches the
    // #140 re-anchor in the stored frame: east of UTC the raw local midnight
    // is the previous UTC day. A daily rule fits any anchor, so the re-anchor
    // keeps the start as shifted.
    @Test
    fun resolveTargetStart_allDayDayMoveWithNewRule_returnsStoredMidnight() {
        val result = resolve(
            instantAt(sydney, 2026, 6, 7),
            zone = sydney,
            newRule = "FREQ=DAILY"
        )
        assertEquals(stored(7), result.getOrThrow())
    }
}
