package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * [resolveSeriesTimes] on a series stored with millis (an older plugin
 * version, or another app): it keeps that start when nothing moves the
 * anchor, and writes whole seconds when a rule re-anchors it. The plugin can
 * no longer write such a row, so no integration test can set one up (#165).
 */
internal class SeriesTimesTest {
    private val newYork = TimeZone.getTimeZone("America/New_York")

    private fun ny(month: Int, day: Int, hour: Int) =
        instantAt(newYork, 2026, month, day, hour)

    /** An allEvents edit of a series stored at [stored], with no new start. */
    private fun resolve(
        stored: Long,
        duration: Long = 3_600_000L,
        durationMinutes: Int? = null,
        rrule: String? = null
    ) = resolveSeriesTimes(
        baseMillis = stored,
        referenceMillis = stored,
        existingDurationMillis = duration,
        newStartMillis = null,
        durationMinutes = durationMinutes,
        rrule = rrule,
        timeZoneId = "America/New_York",
        isAllDay = false
    ).getOrThrow()

    // Rewriting the start would orphan detached occurrences keyed at the
    // millis anchor, and a duration-only edit does rewrite DTSTART.
    @Test
    fun resolveSeriesTimes_withoutRule_storedWithMillis_keepsStoredStart() {
        val stored = ny(10, 1, 9) + 671
        val (start, _) = resolve(stored = stored, durationMinutes = 30)
        assertEquals(stored, start)
    }

    @Test
    fun resolveSeriesTimes_withRule_storedWithMillis_floorsStart() {
        // 1 Oct 2026 is a Thursday; the rule re-anchors to Friday.
        val (start, _) = resolve(stored = ny(10, 1, 9) + 671, rrule = "FREQ=WEEKLY;BYDAY=FR")
        assertEquals(ny(10, 2, 9), start)
    }

    // A stored DTEND whose millis differ from DTSTART's gives a sub-second
    // duration. The duration is written as whole seconds; the end is whole
    // when the start is.
    @Test
    fun resolveSeriesTimes_storedDurationWithMillis_floorsDuration() {
        val (start, duration) = resolve(stored = ny(10, 1, 9), duration = 3_600_671L)
        assertEquals(3_600_000L, duration)
        assertEquals(ny(10, 1, 10), start + duration)
    }

    // A millis start nothing moves is kept, so the end written from it
    // (start + floored duration) keeps those millis on purpose.
    @Test
    fun resolveSeriesTimes_storedStartAndDurationWithMillis_endKeepsStartMillis() {
        val stored = ny(10, 1, 9) + 671
        val (start, duration) = resolve(stored = stored, duration = 3_600_671L)
        assertEquals(stored, start)
        assertEquals(ny(10, 1, 10) + 671, start + duration)
    }
}
