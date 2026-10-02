package to.bullet.device_calendar_plus_android

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import org.mockito.ArgumentMatchers.anyBoolean
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Status decisions for a context without an Activity (a background isolate,
 * a WorkManager job), which an integration test can't set up.
 */
internal class PermissionServiceTest {
    /**
     * A plain (non-Activity) [Context] that declares both calendar
     * permissions, with the plugin's was-denied flag set to [wasDenied].
     */
    private fun backgroundContext(wasDenied: Boolean): Context {
        val packageInfo = PackageInfo().apply {
            requestedPermissions = arrayOf(
                Manifest.permission.READ_CALENDAR,
                Manifest.permission.WRITE_CALENDAR,
            )
        }
        val packageManager = Mockito.mock(PackageManager::class.java)
        Mockito.`when`(packageManager.getPackageInfo(anyString(), anyInt()))
            .thenReturn(packageInfo)

        val prefs = Mockito.mock(SharedPreferences::class.java)
        Mockito.`when`(prefs.getBoolean(anyString(), anyBoolean()))
            .thenReturn(wasDenied)

        return Mockito.mock(Context::class.java).also {
            Mockito.`when`(it.packageName).thenReturn("to.bullet.test")
            Mockito.`when`(it.packageManager).thenReturn(packageManager)
            Mockito.`when`(it.getSharedPreferences(anyString(), anyInt()))
                .thenReturn(prefs)
        }
    }

    @Test
    fun `hasPermissions without an Activity reports denied when a denial is recorded`() {
        // #127: the was-denied flag needs no Activity, so a recorded denial
        // must not read as notDetermined — requestPermissions can't show the
        // dialog from this context anyway.
        val service = PermissionService(backgroundContext(wasDenied = true)) { false }

        assertEquals(PermissionService.STATUS_DENIED, service.hasPermissions().getOrThrow())
    }

    @Test
    fun `hasPermissions without an Activity reports notDetermined when never denied`() {
        val service = PermissionService(backgroundContext(wasDenied = false)) { false }

        assertEquals(PermissionService.STATUS_NOT_DETERMINED, service.hasPermissions().getOrThrow())
    }
}
