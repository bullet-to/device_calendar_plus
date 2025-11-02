package to.bullet.device_calendar_plus_android

import android.app.Activity
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

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var permissionService: PermissionService? = null
    private var calendarService: CalendarService? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_calendar_plus_android")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> handleGetPlatformVersion(result)
            "requestPermissions" -> handleRequestPermissions(result)
            "listCalendars" -> handleListCalendars(result)
            else -> result.notImplemented()
        }
    }

    private fun handleGetPlatformVersion(result: Result) {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
    }

    private fun handleRequestPermissions(result: Result) {
        val service = permissionService!!
        
        service.requestPermissions { serviceResult ->
            serviceResult.fold(
                onSuccess = { status -> result.success(status) },
                onFailure = { error ->
                    if (error is PermissionException) {
                        result.error(error.code, error.message, null)
                    } else {
                        result.error("UNKNOWN_ERROR", error.message, null)
                    }
                }
            )
        }
    }
    
    private fun handleListCalendars(result: Result) {
        val service = calendarService!!
        
        val serviceResult = service.listCalendars()
        serviceResult.fold(
            onSuccess = { calendars -> result.success(calendars) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error("UNKNOWN_ERROR", error.message, null)
                }
            }
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        return permissionService?.onRequestPermissionsResult(requestCode, permissions, grantResults) ?: false
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        permissionService = PermissionService(binding.activity)
        calendarService = CalendarService(binding.activity)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        permissionService = null
        calendarService = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        permissionService = PermissionService(binding.activity)
        calendarService = CalendarService(binding.activity)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
        permissionService = null
        calendarService = null
    }
}
