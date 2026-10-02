package to.bullet.device_calendar_plus_android

import android.Manifest
import android.content.Context
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Status decisions for a context without an Activity (a background isolate,
 * a WorkManager job), which an integration test can't set up.
 */
internal class PermissionServiceTest {
    /**
     * A service on a plain (non-Activity) [Context] whose manifest declares
     * both calendar permissions, none granted, with the was-denied flag set to
     * [wasDenied].
     */
    private fun backgroundService(wasDenied: Boolean) = PermissionService(
        Mockito.mock(Context::class.java),
        isGranted = { false },
        wasDeniedBefore = { wasDenied },
        declaredPermissions = {
            listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
        },
    )

    @Test
    fun hasPermissions_withNoActivityAndRecordedDenial_reportsDenied() {
        // #127: the was-denied flag needs no Activity, so a recorded denial
        // must not read as notDetermined — requestPermissions can't show the
        // dialog from this context anyway.
        val service = backgroundService(wasDenied = true)

        assertEquals(PermissionService.STATUS_DENIED, service.hasPermissions().getOrThrow())
    }

    @Test
    fun hasPermissions_withNoActivityAndNoRecordedDenial_reportsNotDetermined() {
        val service = backgroundService(wasDenied = false)

        assertEquals(PermissionService.STATUS_NOT_DETERMINED, service.hasPermissions().getOrThrow())
    }
}
