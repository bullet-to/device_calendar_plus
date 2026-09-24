package to.bullet.device_calendar_plus_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * `storedEndMillis` derives a row's end from DTEND, else DTSTART + DURATION:
 * a recurring master stores DURATION with a NULL DTEND (#122).
 */
internal class EventTimingTest {
    // "P{n}S" is the form the plugin writes (the timed-master integration
    // test reaches it); other apps and sync adapters write the ISO form,
    // which the integration tests never do.
    @Test
    fun storedEndMillis_parsesEveryDurationForm() {
        assertEquals(1_000L + 3_600_000L, storedEndMillis(1_000L, null, "P3600S"))
        assertEquals(3_600_000L, storedEndMillis(0L, null, "PT1H"))
        assertEquals(86_400_000L, storedEndMillis(0L, null, "P1D"))
        assertEquals(
            ((7 + 2) * 86_400L + 3 * 3_600L + 4 * 60L + 5L) * 1_000L,
            storedEndMillis(0L, null, "P1W2DT3H4M5S"),
        )
        // DTEND wins over DURATION when both are stored.
        assertEquals(2_000L, storedEndMillis(1_000L, 2_000L, "P1D"))
    }

    // The fallthrough buildEventMapFromCursor's `?: rawStart` relies on; no
    // integration test reaches it either.
    @Test
    fun storedEndMillis_unparseableOrAbsentDuration_returnsNull() {
        assertNull(storedEndMillis(0L, null, "garbage"))
        assertNull(storedEndMillis(0L, null, "3600"))
        assertNull(storedEndMillis(0L, null, null))
    }
}
