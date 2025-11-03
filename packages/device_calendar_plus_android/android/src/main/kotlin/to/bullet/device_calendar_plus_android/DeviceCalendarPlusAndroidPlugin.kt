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
    private var eventsService: EventsService? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_calendar_plus_android")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> handleGetPlatformVersion(result)
            "requestPermissions" -> handleRequestPermissions(result)
            "listCalendars" -> handleListCalendars(result)
            "createCalendar" -> handleCreateCalendar(call, result)
            "deleteCalendar" -> handleDeleteCalendar(call, result)
            "retrieveEvents" -> handleRetrieveEvents(call, result)
            "getEvent" -> handleGetEvent(call, result)
            "showEvent" -> handleShowEvent(call, result)
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
                        result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
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
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleCreateCalendar(call: MethodCall, result: Result) {
        val service = calendarService ?: run {
            result.error(PlatformExceptionCodes.UNKNOWN_ERROR, "CalendarService not initialized", null)
            return
        }
        
        // Parse arguments
        val name = call.argument<String>("name")
        val colorHex = call.argument<String>("colorHex")
        
        if (name == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid name",
                null
            )
            return
        }
        
        val serviceResult = service.createCalendar(name, colorHex)
        serviceResult.fold(
            onSuccess = { calendarId -> result.success(calendarId) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleDeleteCalendar(call: MethodCall, result: Result) {
        val service = calendarService ?: run {
            result.error(PlatformExceptionCodes.UNKNOWN_ERROR, "CalendarService not initialized", null)
            return
        }
        
        // Parse arguments
        val calendarId = call.argument<String>("calendarId")
        
        if (calendarId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid calendarId",
                null
            )
            return
        }
        
        val serviceResult = service.deleteCalendar(calendarId)
        serviceResult.fold(
            onSuccess = { result.success(null) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleRetrieveEvents(call: MethodCall, result: Result) {
        val service = eventsService ?: run {
            result.error(PlatformExceptionCodes.UNKNOWN_ERROR, "EventsService not initialized", null)
            return
        }
        
        // Parse arguments
        val startDateMillis = call.argument<Long>("startDate")
        val endDateMillis = call.argument<Long>("endDate")
        val calendarIds = call.argument<List<String>>("calendarIds")
        
        if (startDateMillis == null || endDateMillis == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid startDate or endDate",
                null
            )
            return
        }
        
        val startDate = java.util.Date(startDateMillis)
        val endDate = java.util.Date(endDateMillis)
        
        val serviceResult = service.retrieveEvents(startDate, endDate, calendarIds)
        serviceResult.fold(
            onSuccess = { events -> result.success(events) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleGetEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: run {
            result.error(PlatformExceptionCodes.UNKNOWN_ERROR, "EventsService not initialized", null)
            return
        }
        
        // Parse arguments
        val instanceId = call.argument<String>("instanceId")
        
        if (instanceId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid instanceId",
                null
            )
            return
        }
        
        val serviceResult = service.getEvent(instanceId)
        serviceResult.fold(
            onSuccess = { event -> result.success(event) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleShowEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: run {
            result.error(PlatformExceptionCodes.UNKNOWN_ERROR, "EventsService not initialized", null)
            return
        }
        
        // Parse arguments
        val instanceId = call.argument<String>("instanceId")
        
        if (instanceId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid instanceId",
                null
            )
            return
        }
        
        val serviceResult = service.showEvent(instanceId)
        serviceResult.fold(
            onSuccess = { result.success(null) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
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
        eventsService = EventsService(binding.activity)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        permissionService = null
        calendarService = null
        eventsService = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        permissionService = PermissionService(binding.activity)
        calendarService = CalendarService(binding.activity)
        eventsService = EventsService(binding.activity)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
        permissionService = null
        calendarService = null
        eventsService = null
    }
}
