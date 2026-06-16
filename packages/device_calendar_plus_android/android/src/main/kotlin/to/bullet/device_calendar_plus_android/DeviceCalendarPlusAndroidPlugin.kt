package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** DeviceCalendarPlusAndroidPlugin */
class DeviceCalendarPlusAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private var activity: Activity? = null
    private var permissionService: PermissionService? = null
    private var calendarService: CalendarService? = null
    private var eventsService: EventsService? = null
    private var showEventModalResult: Result? = null
    private var createEventModalResult: Result? = null
    private var providerExecutor: ExecutorService? = null

    // Lazy so constructing the plugin doesn't touch the Looper — JVM unit
    // tests can instantiate the class without an Android runtime.
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    companion object {
        private const val SHOW_EVENT_REQUEST_CODE = 1001
        private const val CREATE_EVENT_REQUEST_CODE = 1002
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_calendar_plus_android")
        channel.setMethodCallHandler(this)

        val context = flutterPluginBinding.applicationContext
        appContext = context
        calendarService = CalendarService(context)
        eventsService = EventsService(context)
        permissionService = PermissionService(context)
        providerExecutor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "DeviceCalendarPlusProvider").apply { isDaemon = true }
        }
    }

    /**
     * Runs a Calendar Provider operation off the main thread and replies on
     * it. ContentResolver calls are blocking binder IPC and method-channel
     * handlers run on the main thread, so query-heavy calls (listEvents fans
     * out one attendees query per event) can ANR there (#73). A single
     * worker keeps operations in call order, as they were when inline.
     */
    private fun <T> runOffMainThread(result: Result, operation: () -> kotlin.Result<T>) {
        providerExecutor!!.execute {
            val serviceResult = try {
                operation()
            } catch (error: Throwable) {
                kotlin.Result.failure(error)
            }
            mainHandler.post {
                serviceResult.fold(
                    // The channel codec can't encode Unit; void operations
                    // reply with null, as the inline handlers did.
                    onSuccess = { value -> result.success(value.takeIf { it != Unit }) },
                    onFailure = { error ->
                        if (error is CalendarException) {
                            result.error(error.code, error.message, null)
                        } else {
                            result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                        }
                    }
                )
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestPermissions" -> handleRequestPermissions(result)
            "hasPermissions" -> handleHasPermissions(result)
            "openAppSettings" -> handleOpenAppSettings(result)
            "listCalendars" -> handleListCalendars(result)
            "listSources" -> handleListSources(result)
            "createCalendar" -> handleCreateCalendar(call, result)
            "updateCalendar" -> handleUpdateCalendar(call, result)
            "deleteCalendar" -> handleDeleteCalendar(call, result)
            "listEvents" -> handleListEvents(call, result)
            "getEvent" -> handleGetEvent(call, result)
            "showEventModal" -> handleShowEventModal(call, result)
            "showCreateEventModal" -> handleShowCreateEventModal(call, result)
            "createEvent" -> handleCreateEvent(call, result)
            "deleteEvent" -> handleDeleteEvent(call, result)
            "updateEvent" -> handleUpdateEvent(call, result)
            "updateRecurring" -> handleUpdateRecurring(call, result)
            "deleteRecurring" -> handleDeleteRecurring(call, result)
            else -> result.notImplemented()
        }
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
    
    private fun handleOpenAppSettings(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error(
                PlatformExceptionCodes.UNKNOWN_ERROR,
                "Activity not available",
                null
            )
            return
        }
        
        try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:${currentActivity.packageName}")
            )
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            currentActivity.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error(
                PlatformExceptionCodes.UNKNOWN_ERROR,
                "Failed to open app settings: ${e.message}",
                null
            )
        }
    }
    
    private fun handleListCalendars(result: Result) {
        val service = calendarService!!

        runOffMainThread(result) { service.listCalendars() }
    }

    private fun handleListSources(result: Result) {
        val service = calendarService!!

        runOffMainThread(result) { service.listSources() }
    }

    private fun handleCreateCalendar(call: MethodCall, result: Result) {
        val service = calendarService ?: error("CalendarService not initialized - plugin lifecycle error")

        // Parse arguments
        val name = call.argument<String>("name")
        val colorHex = call.argument<String>("colorHex")
        val accountName = call.argument<String>("accountName")
        val accountType = call.argument<String>("accountType")
        
        if (name == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid name",
                null
            )
            return
        }
        
        runOffMainThread(result) { service.createCalendar(name, colorHex, accountName, accountType) }
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
        
        runOffMainThread(result) { service.updateCalendar(calendarId, name, colorHex) }
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
        
        runOffMainThread(result) { service.deleteCalendar(calendarId) }
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
        
        runOffMainThread(result) { service.retrieveEvents(startDate, endDate, calendarIds) }
    }
    
    private fun handleGetEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse arguments
        val eventId = call.argument<String>("eventId")
        val timestamp = call.argument<Long>("timestamp")
        
        if (eventId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid eventId",
                null
            )
            return
        }
        
        runOffMainThread(result) { service.getEvent(eventId, timestamp) }
    }
    
    private fun handleShowEventModal(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        val currentActivity = activity ?: error("Activity not initialized - plugin lifecycle error")
        
        // Parse arguments
        val eventId = call.argument<String>("eventId")
        val timestamp = call.argument<Long>("timestamp")
        val edit = call.argument<Boolean>("edit") ?: false

        if (eventId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid eventId",
                null
            )
            return
        }

        // Store the result callback to call when activity returns
        showEventModalResult = result

        val serviceResult = service.showEvent(currentActivity, eventId, timestamp, edit, SHOW_EVENT_REQUEST_CODE)
        serviceResult.fold(
            onSuccess = { /* Result will be sent in onActivityResult */ },
            onFailure = { error ->
                // Clear stored result on error
                showEventModalResult = null
                if (error is CalendarException) {
                    result.error(error.code, error.message, null)
                } else {
                    result.error(PlatformExceptionCodes.UNKNOWN_ERROR, error.message, null)
                }
            }
        )
    }
    
    private fun handleShowCreateEventModal(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        val currentActivity = activity ?: error("Activity not initialized - plugin lifecycle error")

        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()

        createEventModalResult = result

        val serviceResult = service.showCreateEvent(
            activityContext = currentActivity,
            title = args["title"] as? String,
            startDate = args["startDate"] as? Long,
            endDate = args["endDate"] as? Long,
            description = args["description"] as? String,
            location = args["location"] as? String,
            isAllDay = args["isAllDay"] as? Boolean,
            recurrenceRule = args["recurrenceRule"] as? String,
            availability = args["availability"] as? String,
            requestCode = CREATE_EVENT_REQUEST_CODE,
        )
        serviceResult.fold(
            onSuccess = { /* Result will be sent in onActivityResult */ },
            onFailure = { error ->
                createEventModalResult = null
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
        val url = call.argument<String>("url")
        val timeZone = call.argument<String>("timeZone")
        val availability = call.argument<String>("availability")
        val recurrenceRule = call.argument<String>("recurrenceRule")
        
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
        
        runOffMainThread(result) {
            service.createEvent(
                calendarId,
                title,
                startDate,
                endDate,
                isAllDay,
                description,
                location,
                url,
                timeZone,
                availability,
                recurrenceRule
            )
        }
    }
    
    private fun handleDeleteEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse arguments
        val eventId = call.argument<String>("eventId")
        
        if (eventId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid eventId",
                null
            )
            return
        }
        
        val timestamp = call.argument<Long>("timestamp")

        runOffMainThread(result) { service.deleteEvent(eventId, timestamp) }
    }
    
    private fun handleUpdateEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse required arguments
        val eventId = call.argument<String>("eventId")
        
        if (eventId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid eventId",
                null
            )
            return
        }
        
        // Parse optional arguments (all can be null)
        val timestamp = call.argument<Long>("timestamp")
        val startDate = call.argument<Long>("startDate")?.let { java.util.Date(it) }
        val endDate = call.argument<Long>("endDate")?.let { java.util.Date(it) }

        val patch = EventFieldPatch.fromCall(call)

        runOffMainThread(result) {
            service.updateEvent(eventId, timestamp, startDate, endDate, patch)
        }
    }

    private fun handleUpdateRecurring(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")

        val eventId = call.argument<String>("eventId")
        if (eventId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid eventId",
                null
            )
            return
        }

        val span = call.argument<String>("span")
        if (span == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid span",
                null
            )
            return
        }

        // Parse optional arguments (all can be null)
        val timestamp = call.argument<Long>("timestamp")
        val newStartMillis = call.argument<Long>("newStartMillis")
        val durationMinutes = call.argument<Int>("durationMinutes")
        val recurrenceRule = call.argument<String>("recurrenceRule")

        val patch = EventFieldPatch.fromCall(call)

        runOffMainThread(result) {
            service.updateRecurring(
                eventId,
                timestamp,
                span,
                newStartMillis,
                durationMinutes,
                recurrenceRule,
                patch
            )
        }
    }

    private fun handleDeleteRecurring(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")

        val eventId = call.argument<String>("eventId")
        if (eventId == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid eventId",
                null
            )
            return
        }

        val span = call.argument<String>("span")
        if (span == null) {
            result.error(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Missing or invalid span",
                null
            )
            return
        }

        val timestamp = call.argument<Long>("timestamp")

        runOffMainThread(result) { service.deleteRecurring(eventId, timestamp, span) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        return permissionService?.onRequestPermissionsResult(requestCode, permissions, grantResults) ?: false
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?): Boolean {
        if (requestCode == SHOW_EVENT_REQUEST_CODE) {
            showEventModalResult?.success(null)
            showEventModalResult = null
            return true
        }
        if (requestCode == CREATE_EVENT_REQUEST_CODE) {
            createEventModalResult?.success(null)
            createEventModalResult = null
            return true
        }
        return false
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Let in-flight provider work finish; the worker is a daemon thread,
        // so it can't keep the process alive.
        providerExecutor?.shutdown()
        providerExecutor = null
        appContext = null
        calendarService = null
        eventsService = null
        permissionService = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        permissionService = PermissionService(binding.activity)
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        // Downgrade to app context — hasPermissions() still works
        permissionService = appContext?.let { PermissionService(it) }
        showEventModalResult = null
        createEventModalResult = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        permissionService = PermissionService(binding.activity)
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
        // Downgrade to app context — hasPermissions() still works
        permissionService = appContext?.let { PermissionService(it) }
        showEventModalResult = null
        createEventModalResult = null
    }
}
