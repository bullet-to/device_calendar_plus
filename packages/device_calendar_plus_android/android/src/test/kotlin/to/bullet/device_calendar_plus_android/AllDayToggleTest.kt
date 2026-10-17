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
        masterStart: Long,
        durationMillis: Long = hour,
        zone: TimeZone = la,
    ) = resolveSeriesTimeEdit(
        newStartMillis = newStartMillis,
        durationMinutes = durationMinutes,
        rowAllDay = rowAllDay,
        patchIsAllDay = patchIsAllDay,
        defaultStart = defaultStart,
        masterStart = masterStart,
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
    ): Result<SeriesTimes> {
        return resolveSeriesTimes(
            baseMillis = start,
            referenceMillis = start,
            existingDurationMillis = duration,
            timeEdit = timeEdit(
                defaultStart = start,
                masterStart = start,
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
            patchIsAllDay = null, defaultStart = start, masterStart = start
        )

        assertEquals(
            SeriesTimeEdit(null, null, startDefaulted = false, frameChange = FrameChange.None),
            edit
        )
    }

    @Test
    fun resolveSeriesTimeEdit_alreadyAllDay_defaultsNothing() {
        val start = instantAt(utc, 2026, 6, 6)

        val edit = timeEdit(rowAllDay = true, defaultStart = start, masterStart = start)

        assertEquals(
            SeriesTimeEdit(null, null, startDefaulted = false, frameChange = FrameChange.None),
            edit
        )
    }

    @Test
    fun resolveSeriesTimeEdit_toggleWithStartAndDuration_keepsTheCallers() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)
        val given = instantAt(la, 2026, 6, 10)

        val edit = timeEdit(
            newStartMillis = given,
            durationMinutes = 3 * 24 * 60,
            defaultStart = start,
            masterStart = start,
        )

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 10), 3 * 24 * 60, startDefaulted = false,
                frameChange = FrameChange.ToAllDay(la)
            ),
            edit
        )
    }

    @Test
    fun resolveSeriesTimeEdit_toggleWithStartOnly_defaultsTheDuration() {
        val start = instantAt(la, 2026, 6, 6, 23, 30)
        val given = instantAt(la, 2026, 6, 10)

        val edit = timeEdit(
            newStartMillis = given, defaultStart = start, masterStart = start
        )

        // The duration still comes from the first occurrence: 23:30 to
        // 00:30 touches two local dates.
        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 10), 2 * 24 * 60, startDefaulted = false,
                frameChange = FrameChange.ToAllDay(la)
            ),
            edit
        )
    }

    // A split named at a later occurrence starts the new series there: its
    // own start, not the series', is the default, and so are its days.
    @Test
    fun resolveSeriesTimeEdit_splitToggleNamedByLaterOccurrence_defaultsFromThatOccurrence() {
        val occurrence = instantAt(la, 2026, 6, 13, 23, 30)

        val edit = timeEdit(defaultStart = occurrence, masterStart = occurrence)

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 13), 2 * 24 * 60, startDefaulted = true,
                frameChange = FrameChange.ToAllDay(la)
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

        val edit = timeEdit(defaultStart = occurrence, masterStart = seriesStart)

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 13), 24 * 60, startDefaulted = true,
                frameChange = FrameChange.ToAllDay(la)
            ),
            edit
        )
    }

    @Test
    fun resolveSeriesTimeEdit_toggleNamedByMaster_defaultsFromTheSeriesStart() {
        val seriesStart = instantAt(la, 2026, 6, 6, 12)

        val edit = timeEdit(defaultStart = seriesStart, masterStart = seriesStart)

        assertEquals(
            SeriesTimeEdit(
                instantAt(utc, 2026, 6, 6), 24 * 60, startDefaulted = true,
                frameChange = FrameChange.ToAllDay(la)
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
                masterStart = seriesStart,
            ),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY"),
            isAllDay = true,
            timeZoneId = la.id,
            storedZone = la
        ).getOrThrow()

        assertEquals(instantAt(utc, 2026, 1, 6), newStart)
    }

    // The reverse of #186: a toggle off read base and reference, both UTC
    // midnights, in the series' timed zone. The Azores sit at UTC-1 in
    // winter and UTC+0 in summer, so the Monday 5 January start read as
    // Sunday 4 January there and the Monday 1 June occurrence as itself:
    // a one-day move took the start to Monday 5 January, not Tuesday 6.
    @Test
    fun resolveSeriesTimes_toggleOffNamedAcrossDst_movesTheStartByTheLocalDays() {
        val azores = TimeZone.getTimeZone("Atlantic/Azores")
        val seriesStart = instantAt(utc, 2026, 1, 5)
        val occurrence = instantAt(utc, 2026, 6, 1)

        val (newStart, _) = resolveSeriesTimes(
            baseMillis = seriesStart,
            referenceMillis = occurrence,
            existingDurationMillis = AllDayDates.MILLIS_PER_DAY,
            timeEdit = timeEdit(
                newStartMillis = instantAt(azores, 2026, 6, 2, 9),
                rowAllDay = true,
                patchIsAllDay = false,
                defaultStart = occurrence,
                masterStart = seriesStart,
                zone = azores,
            ),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY"),
            isAllDay = false,
            timeZoneId = azores.id,
            storedZone = seriesTimeZone(azores.id, isAllDay = true)
        ).getOrThrow()

        assertEquals(instantAt(azores, 2026, 1, 6, 9), newStart)
    }

    /**
     * The new (start, duration) of a weekly series stored in UTC, its
     * occurrences lasting an hour, after a bare all-day toggle named at its
     * [occurrence] from a device in [zone], the master starting at
     * [masterStart].
     */
    private fun bareToggleNamedAt(
        occurrence: Long,
        masterStart: Long,
        zone: TimeZone,
    ): Pair<Long, Long> =
        resolveSeriesTimes(
            baseMillis = masterStart,
            referenceMillis = occurrence,
            existingDurationMillis = hour,
            timeEdit = timeEdit(
                defaultStart = occurrence,
                masterStart = masterStart,
                zone = zone,
            ),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY;COUNT=4"),
            isAllDay = true,
            timeZoneId = utc.id,
            storedZone = utc
        ).getOrThrow().let { it.start to it.durationMillis }

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
            bareToggleNamedAt(occurrence, masterStart = seriesStart, zone = la),
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
            bareToggleNamedAt(occurrence, masterStart = seriesStart, zone = sydney),
        )
    }

    // A split's detached occurrences carry onto the new series' slots in the
    // frame its anchor moved in. 16:30 in LA is the same UTC date in PDT
    // (the Monday 26 October split) but the next one in PST (the Monday 2
    // November occurrence past the change). Read raw in UTC, the anchor
    // didn't move and that slot landed on Tuesday 3 November, a day off the
    // new series' Monday; brought into the all-day frame first, it stays on
    // its own Monday.
    @Test
    fun resolveSeriesTimes_splitToggleCarry_acrossDst_keepsTheSlotsLocalDate() {
        val occurrence = instantAt(la, 2026, 10, 26, 16, 30)
        val detachedSlot = instantAt(la, 2026, 11, 2, 16, 30)

        val carry = resolveSeriesTimes(
            baseMillis = occurrence,
            referenceMillis = occurrence,
            existingDurationMillis = hour,
            timeEdit = timeEdit(defaultStart = occurrence, masterStart = occurrence),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY"),
            isAllDay = true,
            timeZoneId = la.id,
            storedZone = la
        ).getOrThrow().carry

        assertEquals(instantAt(utc, 2026, 11, 2), carry.slot(detachedSlot))
        // The occurrence's own start keeps its date: the anchor's didn't move.
        assertEquals(detachedSlot, carry.start(detachedSlot))
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
