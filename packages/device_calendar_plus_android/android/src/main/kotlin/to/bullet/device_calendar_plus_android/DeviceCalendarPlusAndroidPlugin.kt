package to.bullet.device_calendar_plus_android

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** DeviceCalendarPlusAndroidPlugin */
class DeviceCalendarPlusAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    
    companion object {
        private const val CALENDAR_PERMISSION_REQUEST_CODE = 2024
        
        // Permission status codes matching CalendarPermissionStatus enum
        private const val STATUS_GRANTED = 0
        private const val STATUS_DENIED = 2
        private const val STATUS_NOT_DETERMINED = 4
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_calendar_plus_android")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "requestPermissions" -> {
                requestCalendarPermissions(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun requestCalendarPermissions(result: Result) {
        val currentActivity = activity!!
        val readPermission = Manifest.permission.READ_CALENDAR
        val writePermission = Manifest.permission.WRITE_CALENDAR

        // Check if permissions are declared in AndroidManifest.xml
        val packageInfo = currentActivity.packageManager.getPackageInfo(
            currentActivity.packageName,
            PackageManager.GET_PERMISSIONS
        )

        val declaredPermissions = packageInfo.requestedPermissions?.toList() ?: emptyList()
        
        if (!declaredPermissions.contains(readPermission) || !declaredPermissions.contains(writePermission)) {
            // Error code must match PlatformExceptionCodes.permissionsNotDeclared
            result.error(
                "PERMISSIONS_NOT_DECLARED",
                "Calendar permissions must be declared in AndroidManifest.xml.\n\n" +
                "Add the following to android/app/src/main/AndroidManifest.xml:\n" +
                "<uses-permission android:name=\"android.permission.READ_CALENDAR\"/>\n" +
                "<uses-permission android:name=\"android.permission.WRITE_CALENDAR\"/>",
                null
            )
            return
        }

        val readGranted = ContextCompat.checkSelfPermission(
            currentActivity,
            readPermission
        ) == PackageManager.PERMISSION_GRANTED

        val writeGranted = ContextCompat.checkSelfPermission(
            currentActivity,
            writePermission
        ) == PackageManager.PERMISSION_GRANTED

        if (readGranted && writeGranted) {
            result.success(STATUS_GRANTED)
            return
        }

        // Store the result to be completed when permission callback is received
        pendingResult = result

        // Request both permissions
        ActivityCompat.requestPermissions(
            currentActivity,
            arrayOf(readPermission, writePermission),
            CALENDAR_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) {
            return false
        }

        val result = pendingResult ?: return false
        pendingResult = null

        // Check if both permissions were granted
        val allGranted = grantResults.isNotEmpty() && 
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        result.success(if (allGranted) STATUS_GRANTED else STATUS_DENIED)
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
