package to.bullet.device_calendar_plus_android

import kotlin.test.Test
import kotlin.test.assertEquals

internal class EventStatusColumnTest {
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
}
