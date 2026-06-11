package to.bullet.device_calendar_plus_android

import android.content.Context
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

internal class EventsServiceTest {
    private val service = EventsService(Mockito.mock(Context::class.java))

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
}
