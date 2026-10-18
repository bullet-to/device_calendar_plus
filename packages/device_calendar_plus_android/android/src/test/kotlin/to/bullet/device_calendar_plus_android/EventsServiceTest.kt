package to.bullet.device_calendar_plus_android

import kotlin.test.Test
import kotlin.test.assertEquals

internal class EventsServiceTest {
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
