package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * [resolveSeriesTimes] writes a re-anchored series at whole seconds, even
 * when the stored series carries millis (an older plugin version, or another
 * app): the plugin can no longer write such a row, so no integration test
 * can set one up (#165).
 */
internal class SeriesTimesTest {
    private val newYork = TimeZone.getTimeZone("America/New_York")

    private fun ny(month: Int, day: Int, hour: Int) =
        instantAt(newYork, 2026, month, day, hour)

    @Test
    fun withoutRule_storedWithMillis_floorsStart() {
        val stored = ny(10, 1, 9) + 671
        val (start, _) = resolveSeriesTimes(
            stored, stored, 3_600_000L, null, null, null, "America/New_York", false
        ).getOrThrow()
        assertEquals(ny(10, 1, 9), start)
    }

    @Test
    fun withRule_storedWithMillis_floorsStart() {
        val stored = ny(10, 1, 9) + 671 // a Thursday
        val (start, _) = resolveSeriesTimes(
            stored, stored, 3_600_000L, null, null,
            "FREQ=WEEKLY;BYDAY=FR", "America/New_York", false
        ).getOrThrow()
        assertEquals(ny(10, 2, 9), start)
    }

    // A stored DTEND whose millis differ from DTSTART's gives a sub-second
    // duration; the end written from it must still land on a whole second.
    @Test
    fun storedDurationWithMillis_floorsDuration() {
        val stored = ny(10, 1, 9)
        val (start, duration) = resolveSeriesTimes(
            stored, stored, 3_600_671L, null, null, null, "America/New_York", false
        ).getOrThrow()
        assertEquals(0L, (start + duration) % 1000)
    }
}
