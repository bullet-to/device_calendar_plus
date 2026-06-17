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
     * The access tier implied purely by which calendar permissions are
     * currently granted: [STATUS_GRANTED] (read + write), [STATUS_WRITE_ONLY]
     * (write alone — genuine add-only access, mirroring iOS 17+), or `null` when
     * write access isn't held. A `null` means there is no positive tier, so the
     * caller decides whether that reads as denied or not-yet-determined.
     */
    private fun grantedTier(): String? {
        val readGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED

        val writeGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED

        return when {
            readGranted && writeGranted -> STATUS_GRANTED
            writeGranted -> STATUS_WRITE_ONLY
            else -> null
        }
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
     * Decision logic when write access isn't held (keyed off WRITE_CALENDAR
     * alone — the capability that defines whether any tier is reachable):
     * - `shouldShowRationale == false` AND SharedPrefs flag set --> [STATUS_DENIED] (permanently denied, must use app settings)
     * - everything else --> [STATUS_NOT_DETERMINED] (permission dialog can still be shown)
     *
     * Based on the approach from Baseflow's flutter-permission-handler:
     * https://github.com/Baseflow/flutter-permission-handler/blob/39fba431428e5d82d35f4999663461468fe3a728/permission_handler_android/android/src/main/java/com/baseflow/permissionhandler/PermissionUtils.java#L400-L536
     */
    private fun getCurrentPermissionStatus(): String {
        // Holding write access is a positive tier (full or write-only).
        grantedTier()?.let { return it }

        // Otherwise write isn't granted. Distinguish "never asked / can ask
        // again" (NOT_DETERMINED) from "permanently denied" (DENIED). WRITE is
        // the capability that defines whether any tier is reachable (a held
        // READ-only state isn't possible — grantedTier already returned for any
        // write-bearing tier), so the decision keys off WRITE alone.
        val writePermission = Manifest.permission.WRITE_CALENDAR

        // Without an Activity we can't check shouldShowRequestPermissionRationale,
        // so fall back to NOT_DETERMINED (safe default — caller can still request).
        val currentActivity = activity ?: return STATUS_NOT_DETERMINED

        val permanentlyDenied = wasPermissionDeniedBefore(writePermission) &&
            !ActivityCompat.shouldShowRequestPermissionRationale(currentActivity, writePermission)

        return if (permanentlyDenied) STATUS_DENIED else STATUS_NOT_DETERMINED
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

        // A dismissed dialog delivers empty arrays — no grant, no denial. Report
        // the real current status (can-ask-again) instead of a hard denial, so a
        // later hasPermissions() doesn't disagree. Mirrors iOS, which re-reads
        // the real status on a dismissed prompt.
        if (grantResults.isEmpty()) {
            callback(Result.success(getCurrentPermissionStatus()))
            return true
        }

        // Record any denials so a later hasPermissions() can tell a permanent
        // denial from a can-ask-again one.
        permissions.forEachIndexed { index, permission ->
            if (grantResults.getOrNull(index) != PackageManager.PERMISSION_GRANTED) {
                setPermissionDenied(permission)
            }
        }

        // Report the tier actually held. WRITE_CALENDAR is the capability that
        // matters: hold it and the app has at least write-only access, so a
        // full request that granted write but denied read reads as writeOnly —
        // not denied — matching iOS, which reports the real tier on a non-full
        // grant. Lacking write, the request was denied. We use STATUS_DENIED
        // here (not getCurrentPermissionStatus's can-ask-again NOT_DETERMINED)
        // because a just-denied request should read as denied, again as on iOS.
        callback(Result.success(grantedTier() ?: STATUS_DENIED))
        return true
    }
}

data class PermissionException(
    val code: String,
    override val message: String
) : Exception(message)

