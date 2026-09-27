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
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * DeviceCalendarPlusAndroidPlugin
 *
 * [newProviderExecutor] and [postToMain] are the threads provider work runs
 * on and replies from; JVM unit tests swap them for ones they drive, since
 * there's no Looper there.
 */
class DeviceCalendarPlusAndroidPlugin internal constructor(
    private val newProviderExecutor: () -> Executor,
    private val postToMain: (() -> Unit) -> Unit,
) :
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
    /** The reply for the native modal that's showing, if any. */
    internal val pendingModal = PendingModal()
    private var providerExecutor: Executor? = null

    constructor() : this(
        newProviderExecutor = {
            Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "DeviceCalendarPlusProvider").apply { isDaemon = true }
            }
        },
        postToMain = { block -> mainHandler.post(block) },
    )

    companion object {
        internal const val SHOW_EVENT_REQUEST_CODE = 1001
        internal const val CREATE_EVENT_REQUEST_CODE = 1002

        // Lazy so constructing the plugin doesn't touch the Looper — JVM unit
        // tests can instantiate the class without an Android runtime.
        private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_calendar_plus_android")
        channel.setMethodCallHandler(this)

        val context = flutterPluginBinding.applicationContext
        appContext = context
        calendarService = CalendarService(context)
        eventsService = EventsService(context, calendarService!!)
        permissionService = PermissionService(context)
        providerExecutor = newProviderExecutor()
    }

    /**
     * Runs a Calendar Provider [operation] off the main thread, then hands
     * its outcome to [then] back on the main thread. ContentResolver calls
     * are blocking binder IPC and method-channel handlers run on the main
     * thread, so query-heavy calls (listEvents fans out one attendees query
     * per event) can ANR there (#73). A single worker keeps operations in
     * call order, as they were when inline. A throw becomes a failure.
     */
    private fun <T> onProvider(operation: () -> kotlin.Result<T>, then: (kotlin.Result<T>) -> Unit) {
        providerExecutor!!.execute {
            val outcome = try {
                operation()
            } catch (error: Throwable) {
                kotlin.Result.failure(error)
            }
            postToMain { then(outcome) }
        }
    }

    /** [onProvider], replying to [result] with the outcome. */
    private fun <T> runOffMainThread(result: Result, operation: () -> kotlin.Result<T>) {
        onProvider(operation) { outcome ->
            outcome.fold(
                // The channel codec can't encode Unit; void operations
                // reply with null, as the inline handlers did.
                onSuccess = { value -> result.success(value.takeIf { it != Unit }) },
                onFailure = { error -> result.error(error.channelCode, error.message, null) }
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestPermissions" -> handleRequestPermissions(call, result)
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

    private fun handleRequestPermissions(call: MethodCall, result: Result) {
        val service = permissionService!!
        val writeOnly = call.argument<Boolean>("writeOnly") ?: false

        service.requestPermissions(writeOnly) { serviceResult ->
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
            // Same condition as requestPermissions' no-Activity failure, so use
            // the same code — callers shouldn't handle two errors for one state.
            result.error(
                PlatformExceptionCodes.OPERATION_FAILED,
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

        launchModalAfterLookup(
            SHOW_EVENT_REQUEST_CODE,
            result,
            lookup = { service.findEventForModal(eventId, timestamp) },
        ) { currentActivity, requestCode, rowId ->
            service.showEvent(currentActivity, rowId, timestamp, edit, requestCode)
        }
    }

    private fun handleShowCreateEventModal(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")

        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()

        // No lookup: ACTION_INSERT needs nothing from the provider.
        launchModalNow(CREATE_EVENT_REQUEST_CODE, result) { currentActivity, requestCode ->
            service.showCreateEvent(
                activityContext = currentActivity,
                title = args["title"] as? String,
                startDate = args["startDate"] as? Long,
                endDate = args["endDate"] as? Long,
                description = args["description"] as? String,
                location = args["location"] as? String,
                isAllDay = args["isAllDay"] as? Boolean,
                recurrenceRule = args["recurrenceRule"] as? String,
                availability = args["availability"] as? String,
                requestCode = requestCode,
            )
        }
    }

    /**
     * Launches a modal with [launch] from the current activity right away,
     * replying to [result] when it closes (from onActivityResult). Every
     * failure — no activity, a modal already showing, the launch — replies
     * once.
     */
    private fun launchModalNow(
        requestCode: Int,
        result: Result,
        launch: (Activity, Int) -> kotlin.Result<Unit>,
    ) {
        val currentActivity = claimModal(requestCode, result) ?: return
        launch(currentActivity, requestCode).onFailure(pendingModal::fail)
    }

    /**
     * [launchModalNow] behind a [lookup] whose value [launch] needs. The
     * lookup is provider IPC, so it runs on the provider executor like every
     * other query (#73). The slot is claimed first, so two calls in one turn
     * can't both get through — as on iOS, which also looks up after claiming.
     */
    private fun <T> launchModalAfterLookup(
        requestCode: Int,
        result: Result,
        lookup: () -> kotlin.Result<T>,
        launch: (Activity, Int, T) -> kotlin.Result<Unit>,
    ) {
        claimModal(requestCode, result) ?: return
        onProvider(lookup) { found ->
            // The claim can be resolved while the lookup runs (the activity
            // went away); then there's nothing left to launch.
            if (!pendingModal.holds(result)) return@onProvider
            found.fold(
                onSuccess = { value ->
                    // The activity can be gone here and not the claim: mid
                    // config change, between detach and reattach. That fails
                    // rather than waiting for the recreated activity — still
                    // exactly one reply.
                    val currentActivity = activity ?: return@fold pendingModal.fail(
                        CalendarException(PlatformExceptionCodes.OPERATION_FAILED, "Activity not available")
                    )
                    launch(currentActivity, requestCode, value).onFailure(pendingModal::fail)
                },
                onFailure = pendingModal::fail,
            )
        }
    }

    /**
     * Claims the modal slot for [requestCode], returning the activity to
     * launch from. With no activity, replies OPERATION_FAILED — the code
     * openAppSettings and requestPermissions use for the same state — and
     * returns null, as it does when the slot is taken.
     */
    private fun claimModal(requestCode: Int, result: Result): Activity? {
        val currentActivity = activity ?: run {
            result.error(PlatformExceptionCodes.OPERATION_FAILED, "Activity not available", null)
            return null
        }
        return currentActivity.takeIf { pendingModal.begin(requestCode, result) }
    }

    private fun handleCreateEvent(call: MethodCall, result: Result) {
        val service = eventsService ?: error("EventsService not initialized - plugin lifecycle error")
        
        // Parse arguments
        val calendarId = call.argument<String>("calendarId")
        val title = call.argument<String>("title")
        val startDateMillis = call.writtenInstant("startDate")
        val endDateMillis = call.writtenInstant("endDate")
        val isAllDay = call.argument<Boolean>("isAllDay")
        val description = call.argument<String>("description")
        val location = call.argument<String>("location")
        val url = call.argument<String>("url")
        val timeZone = call.argument<String>("timeZone")
        val availability = call.argument<String>("availability")
        val recurrenceRule = call.argument<String>("recurrenceRule")
        // Reminders: minutes before start (already normalized by the Dart layer).
        val reminders = call.argument<List<Int>>("reminders")

        // Validate required arguments.
        // calendarId is optional: null routes the event to the default calendar.
        if (title == null || startDateMillis == null ||
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
                recurrenceRule,
                reminders
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
        val startDate = call.writtenInstant("startDate")?.let { java.util.Date(it) }
        val endDate = call.writtenInstant("endDate")?.let { java.util.Date(it) }

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
        val newStartMillis = call.writtenInstant("newStartMillis")
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
        // Only a result for the modal we're waiting on is ours; anything else
        // (including a stray 1001/1002) is left for other listeners.
        return pendingModal.complete(requestCode)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Let in-flight provider work finish; the worker is a daemon thread,
        // so it can't keep the process alive.
        (providerExecutor as? ExecutorService)?.shutdown()
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
        // The pending modal stays: the recreated activity receives its result
        // in onActivityResult (#123).
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
        pendingModal.activityGone()
    }
}

/**
 * A caller-supplied event time that will be written, floored to a whole
 * second. Caller-supplied times are floored here. The only other place is
 * [resolveSeriesTimes], which floors a stored start when a rule re-anchor
 * rewrites it, and keeps a stored duration at whole seconds. iOS EventKit
 * stores whole seconds, and flooring on the way in means everything
 * downstream (the stored columns, and the SplitShift and day-move checks an
 * updateRecurring start drives) sees the value that is stored (#165).
 */
private fun MethodCall.writtenInstant(key: String): Long? =
    argument<Long>(key)?.let(::wholeSeconds)
