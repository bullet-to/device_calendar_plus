package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * updateRecurring's all-day start frames on devices either side of UTC
 * (#144): [resolveTargetStart] and then [resolveSeriesTimes]'s anchor shift
 * and day-move check. A stored all-day occurrence is UTC midnight; the
 * caller's new start arrives from Dart as the device-local midnight of the
 * day it means, and must be brought into the stored frame before the anchor
 * shift uses it and the day-move check reads the start it produces. Each
 * case runs the start on through [resolveSeriesTimes], as an allEvents edit
 * does, and reads back the series' new start. 2026-06-06 is a Saturday.
 */
internal class AllDayStartFrameTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val la = TimeZone.getTimeZone("America/Los_Angeles")
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")

    /** The June [day]'s all-day occurrence, as the provider stores it. */
    private fun stored(day: Int) = instantAt(utc, 2026, 6, day)

    /**
     * Moves a series stored at [base] in [storedZone] (UTC, as all-day is
     * stored, unless the series was timed) to [newStart] from a device in
     * [zone], and returns the series' new start. [effectiveIsAllDay] is the
     * series' frame after the edit. [ruleEdit] defaults to keeping a
     * Saturday rule; a replacing rule lifts the day-move check.
     */
    private fun resolve(
        newStart: Long,
        effectiveIsAllDay: Boolean = true,
        ruleEdit: SeriesRuleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY;BYDAY=SA"),
        zone: TimeZone = la,
        base: Long = stored(6),
        storedZone: TimeZone = utc
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
        ruleEdit = ruleEdit,
        splitsSeries = false,
        isAllDay = effectiveIsAllDay,
        timeZoneId = zone.id,
        storedZone = storedZone
    ).map { it.first }

    /**
     * Moves an all-day [rrule] series stored on Saturday 6 June to the local
     * midnight of June [newDay], from a device in [zone].
     */
    private fun moveAllDay(rrule: String, newDay: Int, zone: TimeZone) =
        resolve(
            instantAt(zone, 2026, 6, newDay),
            ruleEdit = SeriesRuleEdit.Keep(rrule),
            zone = zone
        )

    // West of UTC the stored UTC midnight is the previous local evening:
    // read in the device zone it looked like a Friday, so keeping the
    // Saturday was refused and moving to the Friday let through.
    @Test
    fun resolveSeriesTimes_allDaySameDayWestOfUtc_returnsStoredMidnight() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, la)
        assertEquals(stored(6), result.getOrThrow())
    }

    @Test
    fun resolveSeriesTimes_allDayDayEarlierWestOfUtc_refused() {
        moveAllDay("FREQ=WEEKLY;BYDAY=SA", 5, la).assertRefused()
    }

    @Test
    fun resolveSeriesTimes_allDayMonthDayMoveWestOfUtc_refused() {
        moveAllDay("FREQ=MONTHLY;BYMONTHDAY=6", 5, la).assertRefused()
    }

    @Test
    fun resolveSeriesTimes_allDaySameDayEastOfUtc_returnsStoredMidnight() {
        val result = moveAllDay("FREQ=WEEKLY;BYDAY=SA", 6, sydney)
        assertEquals(stored(6), result.getOrThrow())
    }

    @Test
    fun resolveSeriesTimes_allDayDayLaterEastOfUtc_refused() {
        moveAllDay("FREQ=WEEKLY;BYDAY=SA", 7, sydney).assertRefused()
    }

    // East of UTC a local midnight is the previous UTC day: passed on
    // unconverted, a one-day move counted zero days and left the series put.
    @Test
    fun resolveSeriesTimes_allDayDayLaterEastOfUtcImplicitRule_returnsNextStoredMidnight() {
        val result = moveAllDay("FREQ=DAILY;COUNT=4", 7, sydney)
        assertEquals(stored(7), result.getOrThrow())
    }

    @Test
    fun resolveSeriesTimes_allDayDayLaterWestOfUtcImplicitRule_returnsNextStoredMidnight() {
        val result = moveAllDay("FREQ=DAILY;COUNT=4", 7, la)
        assertEquals(stored(7), result.getOrThrow())
    }

    // The same edit toggles all-day off: the new timed start is read in the
    // row's zone, not the UTC of the stored all-day start.
    @Test
    fun resolveSeriesTimes_allDayToTimedSameDay_returnsTimedStart() {
        val newStart = instantAt(la, 2026, 6, 6, 9)
        val result = resolve(newStart, effectiveIsAllDay = false)
        assertEquals(newStart, result.getOrThrow())
    }

    @Test
    fun resolveSeriesTimes_allDayToTimedDayEarlier_refused() {
        resolve(instantAt(la, 2026, 6, 5, 9), effectiveIsAllDay = false).assertRefused()
    }

    // The same edit toggles a Saturday 20:00 Los Angeles series (Sunday in
    // UTC) all-day: its local Saturday midnight becomes Saturday's UTC
    // midnight, which the rule generates.
    @Test
    fun resolveSeriesTimes_timedToAllDaySameDay_returnsStoredMidnight() {
        val result = resolve(
            instantAt(la, 2026, 6, 6),
            base = instantAt(la, 2026, 6, 6, 20),
            storedZone = la
        )
        assertEquals(stored(6), result.getOrThrow())
    }

    // The flip side, mirroring Swift's
    // testAllDayToggleOntoTheNextLocalDayOfTheStoredDayIsRefused: a
    // Wednesday-23:00-UTC series shows on Thursday in Sydney, but the weekday
    // it pins is the stored-zone one. Toggling it all-day onto the Thursday
    // it shows on lands on a day the rule doesn't generate, so it needs a
    // new rule like any other day move. 1 October 2026 is a Thursday.
    @Test
    fun resolveSeriesTimes_timedToAllDayOntoNextLocalDayEastOfUtc_refused() {
        resolve(
            instantAt(sydney, 2026, 10, 1),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY;BYDAY=WE"),
            zone = sydney,
            base = instantAt(utc, 2026, 9, 30, 23),
            storedZone = utc
        ).assertRefused()
    }

    // A new rule lifts the day-move check, but the start still reaches the
    // #140 re-anchor in the stored frame: east of UTC the raw local midnight
    // is the previous UTC day. A daily rule fits any anchor, so the re-anchor
    // keeps the start as shifted.
    @Test
    fun resolveSeriesTimes_allDayDayMoveWithNewRule_returnsStoredMidnight() {
        val result = resolve(
            instantAt(sydney, 2026, 6, 7),
            zone = sydney,
            ruleEdit = SeriesRuleEdit.Replace("FREQ=DAILY")
        )
        assertEquals(stored(7), result.getOrThrow())
    }
}
