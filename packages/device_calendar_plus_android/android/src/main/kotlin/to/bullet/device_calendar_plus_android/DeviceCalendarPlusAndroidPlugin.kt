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
            "hasPermissions" -> handleHasPermissions(result)
            "listCalendars" -> handleListCalendars(result)
            "createCalendar" -> handleCreateCalendar(call, result)
            "updateCalendar" -> handleUpdateCalendar(call, result)
            "deleteCalendar" -> handleDeleteCalendar(call, result)
            "listEvents" -> handleListEvents(call, result)
            "getEvent" -> handleGetEvent(call, result)
            "showEventModal" -> handleShowEventModal(call, result)
            "createEvent" -> handleCreateEvent(call, result)
            "deleteEvent" -> handleDeleteEvent(call, result)
            "updateEvent" -> handleUpdateEvent(call, result)
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
    
    private fun handleHasPermissions(result: Result) {
        val service = permissionService!!
        
        val serviceResult = service.hasPermissions()
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
        val service = calendarService ?: error("CalendarService not initialized - plugin lifecycle error")
        
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
    
    private fun handleUpdateCalendar(call: MethodCall, result: Result) {
        val service = calendarService ?: error("CalendarService not initialized - plugin lifecycle error")
        
        // Parse arguments
        val calendarId = call.argument<String>("calendarId")
        val name = call.argument<String>("name")
        val colorHex = call.argument<String>("colorHex")
        
        if (calendarId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid calendarId",
                null
            )
            return
        }
        
        val serviceResult = service.updateCalendar(calendarId, name, colorHex)
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
    
    private fun handleDeleteCalendar(call: MethodCall, result: Result) {
        val service = calendarService ?: error("CalendarService not initialized - plugin lifecycle error")
        
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
    
    private fun handleListEvents(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
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
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
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
    
    private fun handleShowEventModal(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
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
    
    private fun handleCreateEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse arguments
        val calendarId = call.argument<String>("calendarId")
        val title = call.argument<String>("title")
        val startDateMillis = call.argument<Long>("startDate")
        val endDateMillis = call.argument<Long>("endDate")
        val isAllDay = call.argument<Boolean>("isAllDay")
        val description = call.argument<String>("description")
        val location = call.argument<String>("location")
        val timeZone = call.argument<String>("timeZone")
        val availability = call.argument<String>("availability")
        
        // Validate required arguments
        if (calendarId == null || title == null || startDateMillis == null || 
            endDateMillis == null || isAllDay == null || availability == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing required arguments for createEvent",
                null
            )
            return
        }
        
        val startDate = java.util.Date(startDateMillis)
        val endDate = java.util.Date(endDateMillis)
        
        val serviceResult = service.createEvent(
            calendarId,
            title,
            startDate,
            endDate,
            isAllDay,
            description,
            location,
            timeZone,
            availability
        )
        
        serviceResult.fold(
            onSuccess = { eventId -> result.success(eventId) },
            onFailure = { error ->
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleDeleteEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse arguments
        val instanceId = call.argument<String>("instanceId")
        val deleteAllInstances = call.argument<Boolean>("deleteAllInstances")
        
        if (instanceId == null || deleteAllInstances == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing required arguments for deleteEvent",
                null
            )
            return
        }
        
        val serviceResult = service.deleteEvent(instanceId, deleteAllInstances)
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
    
    private fun handleUpdateEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse required arguments
        val instanceId = call.argument<String>("instanceId")
        val updateAllInstances = call.argument<Boolean>("updateAllInstances")
        
        if (instanceId == null || updateAllInstances == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing required arguments for updateEvent",
                null
            )
            return
        }
        
        // Parse optional arguments (all can be null)
        val title = call.argument<String>("title")
        val startDateMillis = call.argument<Long>("startDate")
        val endDateMillis = call.argument<Long>("endDate")
        val description = call.argument<String>("description")
        val location = call.argument<String>("location")
        val isAllDay = call.argument<Boolean>("isAllDay")
        val timeZone = call.argument<String>("timeZone")
        val availability = call.argument<String>("availability")
        
        // Convert dates if provided
        val startDate = startDateMillis?.let { java.util.Date(it) }
        val endDate = endDateMillis?.let { java.util.Date(it) }
        
        val serviceResult = service.updateEvent(
            instanceId,
            updateAllInstances,
            title,
            startDate,
            endDate,
            description,
            location,
            isAllDay,
            timeZone,
            availability
        )
        
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
