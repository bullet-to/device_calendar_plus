package to.bullet.device_calendar_plus_android

import android.content.Context
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class EventsServiceTest {
    private val service = EventsService(
        Mockito.mock(Context::class.java),
        Mockito.mock(CalendarService::class.java),
    )

    // Regression: a NULL STATUS column used to be read as 0, which is
    // STATUS_TENTATIVE on Android — events with no status came back as
    // "tentative" instead of "none".
    @Test
    fun statusToString_null_returnsNone() {
        assertEquals("none", service.statusToString(null))
    }

    @Test
    fun statusToString_mapsProviderConstants() {
        assertEquals("tentative", service.statusToString(0))
        assertEquals("confirmed", service.statusToString(1))
        assertEquals("canceled", service.statusToString(2))
    }

    // A NULL AVAILABILITY column falls through to the documented default.
    @Test
    fun availabilityToString_null_returnsBusy() {
        assertEquals("busy", service.availabilityToString(null))
    }

    @Test
    fun availabilityToString_mapsProviderConstants() {
        assertEquals("busy", service.availabilityToString(0))
        assertEquals("free", service.availabilityToString(1))
        assertEquals("tentative", service.availabilityToString(2))
    }

    // A recurring master stores DURATION with a NULL DTEND (#122). "P{n}S" is
    // the form the plugin writes, so the timed-master integration test covers
    // it too; it is here as the parser-format case.
    @Test
    fun storedEndMillis_secondsForm_addsDuration() {
        assertEquals(1_000L + 3_600_000L, service.storedEndMillis(1_000L, null, "P3600S"))
    }

    // Other apps and sync adapters write the ISO form, which the integration
    // tests never reach.
    @Test
    fun storedEndMillis_isoForm_addsDuration() {
        assertEquals(3_600_000L, service.storedEndMillis(0L, null, "PT1H"))
        assertEquals(86_400_000L, service.storedEndMillis(0L, null, "P1D"))
        assertEquals(
            ((7 + 2) * 86_400L + 3 * 3_600L + 4 * 60L + 5L) * 1_000L,
            service.storedEndMillis(0L, null, "P1W2DT3H4M5S"),
        )
    }

    // The precedence the read path and the write path (eventDurationMillis)
    // both rely on.
    @Test
    fun storedEndMillis_dtendPresent_ignoresDuration() {
        assertEquals(2_000L, service.storedEndMillis(1_000L, 2_000L, "P1D"))
    }

    // The fallthrough buildEventMapFromCursor's `?: rawStart` relies on; no
    // integration test reaches it either.
    @Test
    fun storedEndMillis_unparseableOrAbsentDuration_returnsNull() {
        assertNull(service.storedEndMillis(0L, null, "garbage"))
        assertNull(service.storedEndMillis(0L, null, "3600"))
        assertNull(service.storedEndMillis(0L, null, null))
    }
}
