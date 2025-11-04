package to.bullet.device_calendar_plus_android

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class PermissionService(private val activity: Activity) {
    
    companion object {
        const val CALENDAR_PERMISSION_REQUEST_CODE = 2024
        
        // Permission status values matching CalendarPermissionStatus enum
        const val STATUS_GRANTED = "granted"
        const val STATUS_DENIED = "denied"
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
        
        return if (readGranted && writeGranted) STATUS_GRANTED else STATUS_DENIED
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
        
        callback(Result.success(if (allGranted) STATUS_GRANTED else STATUS_DENIED))
        return true
    }
}

data class PermissionException(
    val code: String,
    override val message: String
) : Exception(message)

