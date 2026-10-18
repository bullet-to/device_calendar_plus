package to.bullet.device_calendar_plus_android

import kotlin.test.Test
import kotlin.test.assertEquals

internal class EventsServiceTest {
    // Regression: a NULL STATUS column used to be read as 0, which is
    // STATUS_TENTATIVE on Android — events with no status came back as
    // "tentative" instead of "none".
    @Test
    fun statusToString_null_returnsNone() {
        assertEquals("none", statusToString(null))
    }

    @Test
    fun statusToString_mapsProviderConstants() {
        assertEquals("tentative", statusToString(0))
        assertEquals("confirmed", statusToString(1))
        assertEquals("canceled", statusToString(2))
    }

    // A NULL AVAILABILITY column falls through to the documented default.
    @Test
    fun availabilityToString_null_returnsBusy() {
        assertEquals("busy", availabilityToString(null))
    }

    @Test
    fun availabilityToString_mapsProviderConstants() {
        assertEquals("busy", availabilityToString(0))
        assertEquals("free", availabilityToString(1))
        assertEquals("tentative", availabilityToString(2))
    }
}
