package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * updateRecurring toggling a timed series all-day with no `start` or
 * `duration` (#124): the occurrence's own start stands in for `start`, and
 * [allDayToggleDurationMinutes] for `duration`, so the series lands on the
 * occurrence's device-local date, stored as UTC midnight, spanning every
 * local date it touched. The integration test runs on a device in one zone;
 * these cover both sides of UTC, where a timed start's UTC date isn't its
 * local one. The series is stored in UTC, as the integration fixtures store
 * it.
 */
internal class AllDayToggleTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val la = TimeZone.getTimeZone("America/Los_Angeles")
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")

    private val hour = 3_600_000L

    /**
     * The new (start, duration) of a weekly UTC-stored series starting at
     * [start] and lasting [duration], toggled all-day from a device in [zone].
     */
    private fun toggle(start: Long, duration: Long, zone: TimeZone): Pair<Long, Long> =
        resolveSeriesTimes(
            baseMillis = start,
            referenceMillis = start,
            existingDurationMillis = duration,
            targetStart = resolveTargetStart(start, effectiveIsAllDay = true, deviceZone = zone),
            durationMinutes = allDayToggleDurationMinutes(start, duration, zone),
            ruleEdit = SeriesRuleEdit.Keep("FREQ=WEEKLY;COUNT=4"),
            splitsSeries = false,
            isAllDay = true,
            timeZoneId = "UTC",
            storedZone = utc
        ).getOrThrow()

    @Test
    fun toggle_westOfUtc_landsOnTheLocalDateNotTheUtcOne() {
        // 23:30 on 6 June in LA is 06:30 on 7 June UTC.
        val start = instantAt(la, 2026, 6, 6, 23, 30)

        val (newStart, newDuration) = toggle(start, hour, la)

        assertEquals(instantAt(utc, 2026, 6, 6), newStart)
        // 23:30 to 00:30 touches two local dates.
        assertEquals(2 * AllDayDates.MILLIS_PER_DAY, newDuration)
    }

    @Test
    fun toggle_eastOfUtc_landsOnTheLocalDateNotTheUtcOne() {
        // 00:30 on 6 June in Sydney is 14:30 on 5 June UTC.
        val start = instantAt(sydney, 2026, 6, 6, 0, 30)

        val (newStart, newDuration) = toggle(start, hour, sydney)

        assertEquals(instantAt(utc, 2026, 6, 6), newStart)
        assertEquals(AllDayDates.MILLIS_PER_DAY, newDuration)
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
