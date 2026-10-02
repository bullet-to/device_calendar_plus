package to.bullet.device_calendar_plus_android

import android.Manifest
import android.content.Context
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Status decisions that an integration test can't set up: a context without
 * an Activity (a background isolate, a WorkManager job), and the
 * rationale/recorded-denial combinations behind a permanent denial.
 */
internal class PermissionServiceTest {
    /** An in-memory [PermissionDenialStore]. */
    private class FakeDenialStore(vararg denied: String) : PermissionDenialStore {
        private val denied = denied.toMutableSet()

        override fun wasDenied(permission: String) = permission in denied

        override fun recordDenied(permission: String) {
            denied += permission
        }
    }

    private val write = Manifest.permission.WRITE_CALENDAR

    /**
     * A service on a mocked [Context] whose manifest declares both calendar
     * permissions, none granted, with [denials] as the was-denied store and
     * [canAskAgain] as the rationale (`null` stands for no Activity).
     */
    private fun service(
        denials: PermissionDenialStore,
        canAskAgain: Boolean? = null,
    ) = PermissionService(
        Mockito.mock(Context::class.java),
        isGranted = { false },
        denials = denials,
        canAskAgain = { canAskAgain },
        declaredPermissions = {
            listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
        },
    )

    @Test
    fun hasPermissions_withNoActivityAndRecordedDenial_reportsDenied() {
        // #127: the was-denied flag needs no Activity, so a recorded denial
        // must not read as notDetermined — requestPermissions can't show the
        // dialog from this context anyway.
        val service = service(FakeDenialStore(write))

        assertEquals(PermissionService.STATUS_DENIED, service.hasPermissions().getOrThrow())
    }

    @Test
    fun hasPermissions_withNoActivityAndNoRecordedDenial_reportsNotDetermined() {
        val service = service(FakeDenialStore())

        assertEquals(PermissionService.STATUS_NOT_DETERMINED, service.hasPermissions().getOrThrow())
    }

    @Test
    fun hasPermissions_withActivityRationaleAndRecordedDenial_reportsNotDetermined() {
        // Denied once: the OS will still show the dialog, so the app can ask again.
        val service = service(FakeDenialStore(write), canAskAgain = true)

        assertEquals(PermissionService.STATUS_NOT_DETERMINED, service.hasPermissions().getOrThrow())
    }

    @Test
    fun hasPermissions_withActivityNoRationaleAndRecordedDenial_reportsDenied() {
        // Permanently denied: no rationale, and a denial is on record.
        val service = service(FakeDenialStore(write), canAskAgain = false)

        assertEquals(PermissionService.STATUS_DENIED, service.hasPermissions().getOrThrow())
    }
}
