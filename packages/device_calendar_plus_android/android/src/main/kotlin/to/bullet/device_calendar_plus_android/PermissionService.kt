package to.bullet.device_calendar_plus_android

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class PermissionService(private val activity: Activity) {
    
    companion object {
        const val CALENDAR_PERMISSION_REQUEST_CODE = 2024
        
        // Permission status codes matching CalendarPermissionStatus enum
        const val STATUS_GRANTED = 0
        const val STATUS_DENIED = 2
    }
    
    private var pendingCallback: ((Result<Int>) -> Unit)? = null
    
    fun requestPermissions(callback: (Result<Int>) -> Unit) {
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR
        
        // Check if permissions are declared in AndroidManifest.xml
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
            
            callback(Result.failure(PermissionException(PlatformExceptionCodes.PERMISSIONS_NOT_DECLARED, errorMessage)))
            return
        }
        
        val readGranted = ContextCompat.checkSelfPermission(
            activity,
            readPermission
        ) == PackageManager.PERMISSION_GRANTED
        
        val writeGranted = ContextCompat.checkSelfPermission(
            activity,
            writePermission
        ) == PackageManager.PERMISSION_GRANTED
        
        if (readGranted && writeGranted) {
            callback(Result.success(STATUS_GRANTED))
            return
        }
        
        // Store the callback to be completed when permission result is received
        pendingCallback = callback
        
        // Request both permissions
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

