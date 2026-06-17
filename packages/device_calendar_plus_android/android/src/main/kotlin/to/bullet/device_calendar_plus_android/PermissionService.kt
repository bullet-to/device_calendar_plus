package to.bullet.device_calendar_plus_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class PermissionService(private val context: Context) {

    private val activity: Activity?
        get() = context as? Activity
    
    companion object {
        const val CALENDAR_PERMISSION_REQUEST_CODE = 2024
        
        // Permission status values matching CalendarPermissionStatus enum
        const val STATUS_GRANTED = "granted"
        const val STATUS_WRITE_ONLY = "writeOnly"
        const val STATUS_DENIED = "denied"
        const val STATUS_NOT_DETERMINED = "notDetermined"

        private const val PREFS_PERMISSION_WAS_DENIED_BEFORE =
            "device_calendar_plus_permission_was_denied_before"
    }
    
    private var pendingCallback: ((Result<String>) -> Unit)? = null
    
    /**
     * Verifies the manifest declares the permissions the request needs.
     *
     * A write-only request only asks for (and therefore only requires)
     * [Manifest.permission.WRITE_CALENDAR], so an add-only app need not declare
     * [Manifest.permission.READ_CALENDAR]. A full request requires both.
     */
    private fun checkPermissionsDeclared(writeOnly: Boolean): PermissionException? {
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR

        val packageInfo = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_PERMISSIONS
        )

        val declaredPermissions = packageInfo.requestedPermissions?.toList() ?: emptyList()

        val required = if (writeOnly) {
            listOf(writePermission)
        } else {
            listOf(readPermission, writePermission)
        }

        if (required.any { it !in declaredPermissions }) {
            val errorMessage = "Calendar permissions must be declared in AndroidManifest.xml.\n\n" +
                "Add the following to android/app/src/main/AndroidManifest.xml:\n" +
                required.joinToString("\n") { "<uses-permission android:name=\"$it\"/>" }

            return PermissionException(PlatformExceptionCodes.PERMISSIONS_NOT_DECLARED, errorMessage)
        }

        return null
    }

    /**
     * Determines the current calendar permission status, distinguishing between
     * "never asked" ([STATUS_NOT_DETERMINED]) and "denied" ([STATUS_DENIED]).
     *
     * Android's [ContextCompat.checkSelfPermission] returns [PackageManager.PERMISSION_DENIED]
     * both when the user has never been asked and when they actively denied. To distinguish
     * these cases, we combine [ActivityCompat.shouldShowRequestPermissionRationale] with a
     * [android.content.SharedPreferences] flag that records whether a denial has occurred.
     *
     * The OS behavior (experimentally verified) follows this scenario table:
     *
     * | Previous state     | Action  | shouldShowRationale | SharedPrefs flag |
     * |--------------------|---------|---------------------|------------------|
     * | Not asked          | —       | false               | false            |
     * | Denied once        | Denied  | true                | true             |
     * | Denied once        | Dismiss | true                | true             |
     * | Permanently denied | Denied | false              | true             |
     *
     * Decision logic when [PackageManager.PERMISSION_DENIED]:
     * - `shouldShowRationale == false` AND SharedPrefs flag set --> [STATUS_DENIED] (permanently denied, must use app settings)
     * - everything else --> [STATUS_NOT_DETERMINED] (permission dialog can still be shown)
     *
     * Based on the approach from Baseflow's flutter-permission-handler:
     * https://github.com/Baseflow/flutter-permission-handler/blob/39fba431428e5d82d35f4999663461468fe3a728/permission_handler_android/android/src/main/java/com/baseflow/permissionhandler/PermissionUtils.java#L400-L536
     */
    private fun getCurrentPermissionStatus(): String {
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR

        val readGranted = ContextCompat.checkSelfPermission(
            context,
            readPermission
        ) == PackageManager.PERMISSION_GRANTED

        val writeGranted = ContextCompat.checkSelfPermission(
            context,
            writePermission
        ) == PackageManager.PERMISSION_GRANTED

        if (readGranted && writeGranted) return STATUS_GRANTED

        // Write granted but not read is genuine write-only access — the add-only
        // tier requested via CalendarAccessLevel.writeOnly. (Reported on Android
        // too, mirroring iOS 17+.)
        if (writeGranted) return STATUS_WRITE_ONLY

        val deniedPermissions = mutableListOf<String>()
        if (!readGranted) deniedPermissions.add(readPermission)
        if (!writeGranted) deniedPermissions.add(writePermission)

        // Without an Activity we can't check shouldShowRequestPermissionRationale,
        // so fall back to NOT_DETERMINED (safe default — caller can still request).
        val currentActivity = activity ?: return STATUS_NOT_DETERMINED

        val permanentlyDenied = deniedPermissions.any { wasPermissionDeniedBefore(it) } &&
            deniedPermissions.none {
                ActivityCompat.shouldShowRequestPermissionRationale(currentActivity, it)
            }

        if (permanentlyDenied) return STATUS_DENIED

        return STATUS_NOT_DETERMINED
    }

    private fun wasPermissionDeniedBefore(permissionName: String): Boolean {
        val prefs = context.getSharedPreferences(permissionName, Context.MODE_PRIVATE)
        return prefs.getBoolean(PREFS_PERMISSION_WAS_DENIED_BEFORE, false)
    }

    private fun setPermissionDenied(permissionName: String) {
        val prefs = context.getSharedPreferences(permissionName, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(PREFS_PERMISSION_WAS_DENIED_BEFORE, true).apply()
    }
    
    fun hasPermissions(): Result<String> {
        // A status check triggers no request, so only the minimal calendar
        // permission (WRITE) need be declared — an add-only app that omits
        // READ_CALENDAR can still check its status.
        val error = checkPermissionsDeclared(writeOnly = true)
        if (error != null) {
            return Result.failure(error)
        }

        return Result.success(getCurrentPermissionStatus())
    }
    
    /**
     * Requests calendar permissions from the user.
     *
     * @param writeOnly when `true`, requests only [Manifest.permission.WRITE_CALENDAR]
     *   (the add-only tier — mirrors iOS 17+ write-only). When `false`, requests
     *   both [Manifest.permission.READ_CALENDAR] and
     *   [Manifest.permission.WRITE_CALENDAR] for full access.
     */
    fun requestPermissions(writeOnly: Boolean, callback: (Result<String>) -> Unit) {
        val error = checkPermissionsDeclared(writeOnly)
        if (error != null) {
            callback(Result.failure(error))
            return
        }

        val currentStatus = getCurrentPermissionStatus()
        // Full access already satisfies any request. A write-only request is
        // also satisfied when write access is already held.
        if (currentStatus == STATUS_GRANTED ||
            (writeOnly && currentStatus == STATUS_WRITE_ONLY)) {
            callback(Result.success(currentStatus))
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            callback(Result.failure(PermissionException(
                PlatformExceptionCodes.OPERATION_FAILED,
                "Cannot request permissions without an Activity. " +
                    "Use hasPermissions() to check status from a background context."
            )))
            return
        }

        // Store the callback to be completed when permission result is received
        pendingCallback = callback

        // Write-only asks for WRITE_CALENDAR alone; full access asks for both.
        // A full request while write-only is already held only re-prompts for
        // READ_CALENDAR, upgrading the tier.
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR
        val requested = if (writeOnly) {
            arrayOf(writePermission)
        } else {
            arrayOf(readPermission, writePermission)
        }
        ActivityCompat.requestPermissions(
            currentActivity,
            requested,
            CALENDAR_PERMISSION_REQUEST_CODE
        )
    }
    
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) {
            return false
        }
        
        val callback = pendingCallback ?: return false
        pendingCallback = null
        
        // Every requested permission granted? (A write-only request asks for
        // WRITE_CALENDAR alone, so "all" is just that one.)
        val allGranted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        if (!allGranted) {
            permissions.forEachIndexed { index, permission ->
                if (grantResults.getOrNull(index) != PackageManager.PERMISSION_GRANTED) {
                    setPermissionDenied(permission)
                }
            }
            callback(Result.success(STATUS_DENIED))
            return true
        }

        // Report the tier actually held — getCurrentPermissionStatus distinguishes
        // full (read + write) from write-only (write alone), so a granted
        // write-only request resolves to STATUS_WRITE_ONLY.
        callback(Result.success(getCurrentPermissionStatus()))
        return true
    }
}

data class PermissionException(
    val code: String,
    override val message: String
) : Exception(message)

