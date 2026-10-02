package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * updateRecurring toggling a timed series all-day with no `start` or
 * `duration` (#124): [seriesTimeEditDefaults] stands the named occurrence's
 * own start in for `start`, and [allDayToggleDurationMinutes] for
 * `duration`, so the series lands on the occurrence's device-local date,
 * stored as UTC midnight, spanning every local date it touched. The
 * integration test runs on a device in one zone; these cover both sides of
 * UTC, where a timed start's UTC date isn't its local one. The series is
 * stored in UTC, as the integration fixtures store it.
 */
internal class AllDayToggleTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val la = TimeZone.getTimeZone("America/Los_Angeles")
    private val ny = TimeZone.getTimeZone("America/New_York")
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")

    private val hour = 3_600_000L

    private fun defaults(
        newStartMillis: Long? = null,
        durationMinutes: Int? = null,
        rowAllDay: Boolean = false,
        patchIsAllDay: Boolean? = true,
        timestamp: Long? = null,
        seriesStart: Long,
        durationMillis: Long = hour,
        zone: TimeZone = la,
    ) = seriesTimeEditDefaults(
        newStartMillis = newStartMillis,
        durationMinutes = durationMinutes,
        rowAllDay = rowAllDay,
        patchIsAllDay = patchIsAllDay,
        timestamp = timestamp,
        seriesStart = seriesStart,
        durationMillis = durationMillis,
        deviceZone = zone
    )

    /**
     * The new (start, duration) of a series with [rule], starting at [start]
     * and lasting [duration], stored in [storedZone], toggled all-day with
     * only `isAllDay` from a device in [zone], through the defaults
     * updateRecurring takes.
     */
    private fun bareToggle(
        start: Long,
        duration: Long,
        zone: TimeZone,
        rule: String = "FREQ=WEEKLY;COUNT=4",
        seriesZoneId: String = "UTC",
        storedZone: TimeZone = utc,
    ): Result<Pair<Long, Long>> {
        val edit = defaults(seriesStart = start, durationMillis = duration, zone = zone)
        return resolveSeriesTimes(
            baseMillis = start,
            referenceMillis = start,
            existingDurationMillis = duration,
            targetStart = resolveTargetStart(
                edit.startMillis, effectiveIsAllDay = true, deviceZone = zone
            ),
            durationMinutes = edit.durationMinutes,
            ruleEdit = SeriesRuleEdit.Keep(rule),
            splitsSeries = false,
            isAllDay = true,
            timeZoneId = seriesZoneId,
            storedZone = storedZone,
            startDefaulted = edit.startDefaulted
        )
    }

    @Test
    fun seriesTimeEditDefaults_noAllDayChange_passesStartAndDurationThrough() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)

        val edit = defaults(patchIsAllDay = null, seriesStart = start)

        assertEquals(SeriesTimeEdit(null, null, startDefaulted = false), edit)
    }

    @Test
    fun seriesTimeEditDefaults_alreadyAllDay_defaultsNothing() {
        val start = instantAt(utc, 2026, 6, 6)

        val edit = defaults(rowAllDay = true, seriesStart = start)

        assertEquals(SeriesTimeEdit(null, null, startDefaulted = false), edit)
    }

    @Test
    fun seriesTimeEditDefaults_toggleWithStartAndDuration_keepsTheCallers() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)
        val given = instantAt(la, 2026, 6, 10)

        val edit = defaults(
            newStartMillis = given, durationMinutes = 3 * 24 * 60, seriesStart = start
        )

        assertEquals(SeriesTimeEdit(given, 3 * 24 * 60, startDefaulted = false), edit)
    }

    @Test
    fun seriesTimeEditDefaults_toggleWithStartOnly_defaultsTheDuration() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)
        val given = instantAt(la, 2026, 6, 10)

        val edit = defaults(newStartMillis = given, seriesStart = start)

        // The duration still comes from the occurrence: 23:30 to 00:30
        // touches two local dates.
        assertEquals(SeriesTimeEdit(given, 2 * 24 * 60, startDefaulted = false), edit)
    }

    @Test
    fun seriesTimeEditDefaults_toggleNamedByLaterOccurrence_defaultsFromThatOccurrence() {
        val seriesStart = instantAt(la, 2026, 6, 6, 12)
        // A later occurrence: its own start, not the series', is the default.
        val occurrence = instantAt(la, 2026, 6, 13, 23, 30)

        val edit = defaults(timestamp = occurrence, seriesStart = seriesStart)

        assertEquals(SeriesTimeEdit(occurrence, 2 * 24 * 60, startDefaulted = true), edit)
    }

    @Test
    fun seriesTimeEditDefaults_toggleNamedByMaster_defaultsFromTheSeriesStart() {
        val seriesStart = instantAt(la, 2026, 6, 6, 12)

        val edit = defaults(seriesStart = seriesStart)

        assertEquals(SeriesTimeEdit(seriesStart, 24 * 60, startDefaulted = true), edit)
    }

    @Test
    fun resolveSeriesTimes_bareToggleWestOfUtc_landsOnTheLocalDateNotTheUtcOne() {
        // 23:30 on 6 June in LA is 06:30 on 7 June UTC.
        val start = instantAt(la, 2026, 6, 6, 23, 30)

        val (newStart, newDuration) = bareToggle(start, hour, la).getOrThrow()

        assertEquals(instantAt(utc, 2026, 6, 6), newStart)
        // 23:30 to 00:30 touches two local dates.
        assertEquals(2 * AllDayDates.MILLIS_PER_DAY, newDuration)
    }

    @Test
    fun resolveSeriesTimes_bareToggleEastOfUtc_landsOnTheLocalDateNotTheUtcOne() {
        // 00:30 on 6 June in Sydney is 14:30 on 5 June UTC.
        val start = instantAt(sydney, 2026, 6, 6, 0, 30)

        val (newStart, newDuration) = bareToggle(start, hour, sydney).getOrThrow()

        assertEquals(instantAt(utc, 2026, 6, 6), newStart)
        assertEquals(AllDayDates.MILLIS_PER_DAY, newDuration)
    }

    @Test
    fun resolveSeriesTimes_bareToggleOntoADayTheRuleSkips_refusalNamesTheToggle() {
        // A New York Monday series at 10:00 EDT, toggled from a Sydney
        // device, where the occurrence is Tue 2 June 00:00 AEST: the
        // defaulted start lands on a Tuesday the rule doesn't generate.
        val start = instantAt(ny, 2026, 6, 1, 10)
        val result = bareToggle(
            start, hour, sydney,
            rule = "FREQ=WEEKLY;BYDAY=MO",
            seriesZoneId = "America/New_York",
            storedZone = ny,
        )

        val message = result.exceptionOrNull()?.message.orEmpty()
        assertTrue(message.startsWith("isAllDay without a start"), message)
    }

    @Test
    fun allDayToggleDurationMinutes_westOfUtc_spansBothLocalDates() {
        // 23:30 to 00:30 in LA touches 6 and 7 June.
        val start = instantAt(la, 2026, 6, 6, 23, 30)

        assertEquals(2 * 24 * 60, allDayToggleDurationMinutes(start, hour, la))
    }

    @Test
    fun allDayToggleDurationMinutes_zeroDuration_isOneDay() {
        val start = instantAt(la, 2026, 6, 6, 12)

        assertEquals(24 * 60, allDayToggleDurationMinutes(start, 0L, la))
    }

    @Test
    fun allDayToggleDurationMinutes_endingOnLocalMidnight_doesNotTakeTheNextDay() {
        val start = instantAt(la, 2026, 6, 6, 23)

        assertEquals(24 * 60, allDayToggleDurationMinutes(start, hour, la))
    }
}
