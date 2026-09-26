package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * [resolveSeriesTimes] writes a re-anchored series at whole seconds, even
 * when the stored series carries millis (an older plugin version, or another
 * app), and [rewritesSeriesTimes] doesn't count that flooring alone as a
 * move: the plugin can no longer write such a row, so no integration test
 * can set one up (#165).
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

    @Test
    fun withoutRule_storedWithMillis_floorsStart() {
        val (start, _) = resolve(stored = ny(10, 1, 9) + 671)
        assertEquals(ny(10, 1, 9), start)
    }

    @Test
    fun withRule_storedWithMillis_floorsStart() {
        // 1 Oct 2026 is a Thursday; the rule re-anchors to Friday.
        val (start, _) = resolve(stored = ny(10, 1, 9) + 671, rrule = "FREQ=WEEKLY;BYDAY=FR")
        assertEquals(ny(10, 2, 9), start)
    }

    // A stored DTEND whose millis differ from DTSTART's gives a sub-second
    // duration; the end written from it must still land on a whole second.
    @Test
    fun storedDurationWithMillis_floorsDuration() {
        val (_, duration) = resolve(stored = ny(10, 1, 9), duration = 3_600_671L)
        assertEquals(3_600_000L, duration)
    }

    // A title-only edit of a series stored with millis must leave its time
    // columns alone: rewriting them would orphan detached occurrences keyed
    // by the millis anchor and upload a time change on a synced calendar.
    @Test
    fun noTimeChange_storedWithMillis_doesNotRewrite() {
        val stored = ny(10, 1, 9) + 671
        val (start, _) = resolve(stored = stored)
        assertFalse(
            rewritesSeriesTimes(
                storedStart = stored, newStart = start,
                newStartMillis = null, durationMinutes = null
            )
        )
    }

    @Test
    fun reanchoredByRule_storedWithMillis_rewrites() {
        val stored = ny(10, 1, 9) + 671
        val (start, _) = resolve(stored = stored, rrule = "FREQ=WEEKLY;BYDAY=FR")
        assertTrue(
            rewritesSeriesTimes(
                storedStart = stored, newStart = start,
                newStartMillis = null, durationMinutes = null
            )
        )
    }

    @Test
    fun explicitDuration_rewrites() {
        val stored = ny(10, 1, 9)
        val (start, _) = resolve(stored = stored, durationMinutes = 30)
        assertTrue(
            rewritesSeriesTimes(
                storedStart = stored, newStart = start,
                newStartMillis = null, durationMinutes = 30
            )
        )
    }
}
