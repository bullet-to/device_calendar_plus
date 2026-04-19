package to.bullet.device_calendar_plus_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class PermissionService(private val activity: Activity) {
    
    companion object {
        const val CALENDAR_PERMISSION_REQUEST_CODE = 2024
        
        // Permission status values matching CalendarPermissionStatus enum
        const val STATUS_GRANTED = "granted"
        const val STATUS_DENIED = "denied"
        const val STATUS_NOT_DETERMINED = "notDetermined"

        private const val PREFS_PERMISSION_WAS_DENIED_BEFORE =
            "device_calendar_plus_permission_was_denied_before"
    }
    
    private var pendingCallback: ((Result<String>) -> Unit)? = null
    
    private fun checkPermissionsDeclared(): PermissionException? {
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR
        
        val packageInfo = activity.packageManager.getPackageInfo(
            activity.packageName,
            PackageManager.GET_PERMISSIONS
        )
        
        val declaredPermissions = packageInfo.requestedPermissions?.toList() ?: emptyList()
        
        if (!declaredPermissions.contains(readPermission) || !declaredPermissions.contains(writePermission)) {
            val errorMessage = "Calendar permissions must be declared in AndroidManifest.xml.\n\n" +
                "Add the following to android/app/src/main/AndroidManifest.xml:\n" +
                "<uses-permission android:name=\"android.permission.READ_CALENDAR\"/>\n" +
                "<uses-permission android:name=\"android.permission.WRITE_CALENDAR\"/>"
            
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
            activity,
            readPermission
        ) == PackageManager.PERMISSION_GRANTED
        
        val writeGranted = ContextCompat.checkSelfPermission(
            activity,
            writePermission
        ) == PackageManager.PERMISSION_GRANTED
        
        if (readGranted && writeGranted) return STATUS_GRANTED

        val deniedPermissions = mutableListOf<String>()
        if (!readGranted) deniedPermissions.add(readPermission)
        if (!writeGranted) deniedPermissions.add(writePermission)

        val permanentlyDenied = deniedPermissions.any { wasPermissionDeniedBefore(it) } &&
            deniedPermissions.none {
                ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
            }

        if (permanentlyDenied) return STATUS_DENIED

        return STATUS_NOT_DETERMINED
    }

    private fun wasPermissionDeniedBefore(permissionName: String): Boolean {
        val prefs = activity.getSharedPreferences(permissionName, Context.MODE_PRIVATE)
        return prefs.getBoolean(PREFS_PERMISSION_WAS_DENIED_BEFORE, false)
    }

    private fun setPermissionDenied(permissionName: String) {
        val prefs = activity.getSharedPreferences(permissionName, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(PREFS_PERMISSION_WAS_DENIED_BEFORE, true).apply()
    }
    
    fun hasPermissions(): Result<String> {
        val error = checkPermissionsDeclared()
        if (error != null) {
            return Result.failure(error)
        }
        
        return Result.success(getCurrentPermissionStatus())
    }
    
    fun requestPermissions(callback: (Result<String>) -> Unit) {
        val error = checkPermissionsDeclared()
        if (error != null) {
            callback(Result.failure(error))
            return
        }
        
        val currentStatus = getCurrentPermissionStatus()
        if (currentStatus == STATUS_GRANTED) {
            callback(Result.success(STATUS_GRANTED))
            return
        }
        
        // Store the callback to be completed when permission result is received
        pendingCallback = callback
        
        // Request both permissions
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(readPermission, writePermission),
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
        
        // Check if both permissions were granted
        val allGranted = grantResults.isNotEmpty() && 
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        if (!allGranted) {
            permissions.forEachIndexed { index, permission ->
                if (grantResults.getOrNull(index) != PackageManager.PERMISSION_GRANTED) {
                    setPermissionDenied(permission)
                }
            }
        }
        
        callback(Result.success(if (allGranted) STATUS_GRANTED else STATUS_DENIED))
        return true
    }
}

data class PermissionException(
    val code: String,
    override val message: String
) : Exception(message)

