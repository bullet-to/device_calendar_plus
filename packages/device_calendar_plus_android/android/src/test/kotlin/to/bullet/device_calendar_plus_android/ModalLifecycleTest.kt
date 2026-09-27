package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

/** A channel reply that records what it was sent. */
private class RecordingResult : MethodChannel.Result {
    val replies = mutableListOf<String>()

    override fun success(result: Any?) {
        replies.add("success($result)")
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        replies.add("error($errorCode)")
    }

    override fun notImplemented() {
        replies.add("notImplemented")
    }
}

// Regressions for #123: each of these paths used to drop (or crash on) a
// modal's reply, so the Dart await hung or surfaced an unconverted error.
// Every one must now reply exactly once.
internal class ModalLifecycleTest {
    private val showCode = DeviceCalendarPlusAndroidPlugin.SHOW_EVENT_REQUEST_CODE
    private val createCode = DeviceCalendarPlusAndroidPlugin.CREATE_EVENT_REQUEST_CODE

    private val plugin = DeviceCalendarPlusAndroidPlugin().apply {
        val engine = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        Mockito.`when`(engine.binaryMessenger).thenReturn(Mockito.mock(BinaryMessenger::class.java))
        Mockito.`when`(engine.applicationContext).thenReturn(Mockito.mock(Context::class.java))
        onAttachedToEngine(engine)
    }

    private fun activityBinding(): ActivityPluginBinding {
        val binding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(Mockito.mock(Activity::class.java))
        return binding
    }

    /** A modal the plugin is already waiting on, as if its launch succeeded. */
    private fun showingModal(requestCode: Int): RecordingResult {
        plugin.onAttachedToActivity(activityBinding())
        val result = RecordingResult()
        plugin.pendingModal.begin(requestCode, result)
        return result
    }

    private fun call(method: String, arguments: Map<String, Any?> = emptyMap()): RecordingResult {
        val result = RecordingResult()
        plugin.onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    private val operationFailed = listOf("error(${PlatformExceptionCodes.OPERATION_FAILED})")

    @Test
    fun showEventModal_withNoActivity_failsWithOperationFailed() {
        assertEquals(operationFailed, call("showEventModal", mapOf("eventId" to "1")).replies)
    }

    @Test
    fun showCreateEventModal_withNoActivity_failsWithOperationFailed() {
        assertEquals(operationFailed, call("showCreateEventModal").replies)
    }

    @Test
    fun showCreateEventModal_whileAModalIsShowing_failsTheNewCallAndKeepsTheFirst() {
        val first = showingModal(showCode)

        assertEquals(operationFailed, call("showCreateEventModal").replies)
        assertEquals(emptyList(), first.replies)

        plugin.onActivityResult(showCode, Activity.RESULT_OK, null)
        assertEquals(listOf("success(null)"), first.replies)
    }

    @Test
    fun showEventModal_whileAModalIsShowing_failsTheNewCall() {
        showingModal(createCode)

        assertEquals(operationFailed, call("showEventModal", mapOf("eventId" to "1")).replies)
    }

    // Rotation recreates the activity, and the modal's result is delivered to
    // the new one — so the reply has to survive the config-change detach.
    @Test
    fun aConfigChange_carriesThePendingReplyToTheRecreatedActivity() {
        val first = showingModal(showCode)

        plugin.onDetachedFromActivityForConfigChanges()
        plugin.onReattachedToActivityForConfigChanges(activityBinding())
        plugin.onActivityResult(showCode, Activity.RESULT_CANCELED, null)

        assertEquals(listOf("success(null)"), first.replies)
    }

    // No activity will ever deliver the result, so resolve rather than hang.
    @Test
    fun activityDetached_resolvesThePendingReply() {
        val first = showingModal(createCode)

        plugin.onDetachedFromActivity()

        assertEquals(listOf("success(null)"), first.replies)
    }

    @Test
    fun onActivityResult_forTheOtherModal_leavesThePendingReply() {
        val first = showingModal(showCode)

        plugin.onActivityResult(createCode, Activity.RESULT_OK, null)

        assertEquals(emptyList(), first.replies)
    }
}
