package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * updateRecurring toggling a timed series all-day with no `start` or
 * `duration` (#124): [resolveSeriesTimeEdit] defaults them to the named
 * occurrence's own start and [allDayToggleDurationMinutes], so the series
 * lands on the occurrence's device-local date, stored as UTC midnight,
 * spanning every local date it touched. The
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

    private fun timeEdit(
        newStartMillis: Long? = null,
        durationMinutes: Int? = null,
        rowAllDay: Boolean = false,
        patchIsAllDay: Boolean? = true,
        defaultStart: Long,
        firstOccurrenceStart: Long,
        durationMillis: Long = hour,
        zone: TimeZone = la,
    ) = resolveSeriesTimeEdit(
        newStartMillis = newStartMillis,
        durationMinutes = durationMinutes,
        rowAllDay = rowAllDay,
        patchIsAllDay = patchIsAllDay,
        defaultStart = defaultStart,
        firstOccurrenceStart = firstOccurrenceStart,
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
        return resolveSeriesTimes(
            baseMillis = start,
            referenceMillis = start,
            existingDurationMillis = duration,
            timeEdit = timeEdit(
                defaultStart = start,
                firstOccurrenceStart = start,
                durationMillis = duration,
                zone = zone,
            ),
            ruleEdit = SeriesRuleEdit.Keep(rule),
            isAllDay = true,
            timeZoneId = seriesZoneId,
            storedZone = storedZone
        )
    }

    @Test
    fun resolveSeriesTimeEdit_noAllDayChange_passesStartAndDurationThrough() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)

        val edit = timeEdit(
            patchIsAllDay = null, defaultStart = start, firstOccurrenceStart = start
        )

        assertEquals(SeriesTimeEdit(null, null, startDefaulted = false), edit)
    }

    @Test
    fun resolveSeriesTimeEdit_alreadyAllDay_defaultsNothing() {
        val start = instantAt(utc, 2026, 6, 6)

        val edit = timeEdit(rowAllDay = true, defaultStart = start, firstOccurrenceStart = start)

        assertEquals(SeriesTimeEdit(null, null, startDefaulted = false), edit)
    }

    @Test
    fun resolveSeriesTimeEdit_toggleWithStartAndDuration_keepsTheCallers() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)
        val given = instantAt(la, 2026, 6, 10)

        val edit = timeEdit(
            newStartMillis = given,
            durationMinutes = 3 * 24 * 60,
            defaultStart = start,
            firstOccurrenceStart = start,
        )

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 10), 3 * 24 * 60, startDefaulted = false, toAllDayFrom = la
            ),
            edit
        )
    }

    @Test
    fun resolveSeriesTimeEdit_toggleWithStartOnly_defaultsTheDuration() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)
        val given = instantAt(la, 2026, 6, 10)

        val edit = timeEdit(
            newStartMillis = given, defaultStart = start, firstOccurrenceStart = start
        )

        // The duration still comes from the first occurrence: 23:30 to
        // 00:30 touches two local dates.
        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 10), 2 * 24 * 60, startDefaulted = false, toAllDayFrom = la
            ),
            edit
        )
    }

    // A split named at a later occurrence starts the new series there: its
    // own start, not the series', is the default, and so are its days.
    @Test
    fun resolveSeriesTimeEdit_splitToggleNamedByLaterOccurrence_defaultsFromThatOccurrence() {
        val occurrence = instantAt(la, 2026, 6, 13, 23, 30)

        val edit = timeEdit(defaultStart = occurrence, firstOccurrenceStart = occurrence)

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 13), 2 * 24 * 60, startDefaulted = true, toAllDayFrom = la
            ),
            edit
        )
    }

    // An allEvents toggle named at a later occurrence keeps that
    // occurrence's date, but spans the master's days: noon touches one.
    @Test
    fun resolveSeriesTimeEdit_allEventsToggleNamedByLaterOccurrence_spansTheMastersDays() {
        val seriesStart = instantAt(la, 2026, 6, 6, 12)
        val occurrence = instantAt(la, 2026, 6, 13, 23, 30)

        val edit = timeEdit(defaultStart = occurrence, firstOccurrenceStart = seriesStart)

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 13), 24 * 60, startDefaulted = true, toAllDayFrom = la
            ),
            edit
        )
    }

    @Test
    fun resolveSeriesTimeEdit_toggleNamedByMaster_defaultsFromTheSeriesStart() {
        val seriesStart = instantAt(la, 2026, 6, 6, 12)

        val edit = timeEdit(defaultStart = seriesStart, firstOccurrenceStart = seriesStart)

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 6), 24 * 60, startDefaulted = true, toAllDayFrom = la
            ),
            edit
        )
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

        result.assertRefused()
        val message = result.exceptionOrNull()?.message.orEmpty()
        assertTrue(message.startsWith("isAllDay without a start"), message)
    }

    // #186: an allEvents toggle named at an occurrence on the other side of
    // a DST change from the series start. 16:30 in LA is the next UTC date
    // in PST (the Monday 5 January start) but the same one in PDT (the
    // Monday 1 June occurrence). Read in UTC, the occurrence moved one day
    // and the start, a day ahead, moved with it onto 7 January. In local
    // days, as EventKit counts them, a one-day move takes it to 6 January.
    @Test
    fun resolveSeriesTimes_toggleNamedAcrossDst_movesTheStartByTheLocalDays() {
        val seriesStart = instantAt(la, 2026, 1, 5, 16, 30)
        val occurrence = instantAt(la, 2026, 6, 1, 16, 30)

        val (newStart, _) = resolveSeriesTimes(
            baseMillis = seriesStart,
            referenceMillis = occurrence,
            existingDurationMillis = hour,
            timeEdit = timeEdit(
                newStartMillis = instantAt(la, 2026, 6, 2),
                defaultStart = occurrence,
                firstOccurrenceStart = seriesStart,
            ),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY"),
            isAllDay = true,
            timeZoneId = la.id,
            storedZone = la
        ).getOrThrow()

        assertEquals(instantAt(utc, 2026, 1, 6), newStart)
    }

    /**
     * The new (start, duration) of a weekly series stored in UTC, its
     * occurrences lasting an hour, after a bare all-day toggle named at its
     * [occurrence] from a device in [zone]. The series the edit writes starts
     * at [firstOccurrenceStart]: the master's start on allEvents, or
     * [occurrence] itself on a split.
     */
    private fun bareToggleNamedAt(
        occurrence: Long,
        firstOccurrenceStart: Long,
        zone: TimeZone,
    ): Pair<Long, Long> =
        resolveSeriesTimes(
            baseMillis = firstOccurrenceStart,
            referenceMillis = occurrence,
            existingDurationMillis = hour,
            timeEdit = timeEdit(
                defaultStart = occurrence,
                firstOccurrenceStart = firstOccurrenceStart,
                zone = zone,
            ),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY;COUNT=4"),
            isAllDay = true,
            timeZoneId = utc.id,
            storedZone = utc
        ).getOrThrow()

    // #208: a UTC-stored series at 23:30 PDT on Wednesday 28 October runs
    // into Thursday; after the 1 November change its 06:30 UTC occurrences
    // fall at 22:30 PST and stay on their day. An allEvents toggle named at
    // one of those spans the master's two days, as EventKit's does, not the
    // occurrence's one.
    @Test
    fun resolveSeriesTimes_allEventsToggleNamedAcrossDstWestOfUtc_spansTheMastersDays() {
        val seriesStart = instantAt(la, 2026, 10, 28, 23, 30)
        val occurrence = instantAt(la, 2026, 11, 4, 22, 30)

        assertEquals(
            instantAt(utc, 2026, 10, 28) to 2 * AllDayDates.MILLIS_PER_DAY,
            bareToggleNamedAt(occurrence, firstOccurrenceStart = seriesStart, zone = la),
        )
    }

    // East of UTC the change runs the other way: a 00:30 AEDT start on
    // Wednesday 1 April is 13:30 UTC, so once Sydney leaves DST on 5 April
    // the occurrences fall at 23:30 AEST the evening before. Named at one,
    // the toggle keeps the series on the master's Wednesday, one day long.
    @Test
    fun resolveSeriesTimes_allEventsToggleNamedAcrossDstEastOfUtc_staysOnTheMastersDay() {
        val seriesStart = instantAt(sydney, 2026, 4, 1, 0, 30)
        val occurrence = instantAt(sydney, 2026, 4, 7, 23, 30)

        assertEquals(
            instantAt(utc, 2026, 4, 1) to AllDayDates.MILLIS_PER_DAY,
            bareToggleNamedAt(occurrence, firstOccurrenceStart = seriesStart, zone = sydney),
        )
    }

    // A thisAndFollowing toggle starts the new series at the occurrence, so
    // it spans the occurrence's own days, as EventKit's split does.
    @Test
    fun resolveSeriesTimes_splitToggleNamedAcrossDst_spansTheOccurrencesDays() {
        // The master, at 23:30 PDT on 28 October, spans two days.
        val occurrence = instantAt(la, 2026, 11, 4, 22, 30)

        assertEquals(
            instantAt(utc, 2026, 11, 4) to AllDayDates.MILLIS_PER_DAY,
            bareToggleNamedAt(occurrence, firstOccurrenceStart = occurrence, zone = la),
        )
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
