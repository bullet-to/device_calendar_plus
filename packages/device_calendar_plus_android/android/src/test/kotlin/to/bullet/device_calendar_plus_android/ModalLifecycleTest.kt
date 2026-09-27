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
import kotlin.test.assertFalse
import kotlin.test.assertTrue

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

    /** Provider work the test runs by hand, to act while a lookup is in flight. */
    private val providerQueue = ArrayDeque<Runnable>()

    private fun runProviderWork() {
        while (providerQueue.isNotEmpty()) providerQueue.removeFirst().run()
    }

    private val plugin = DeviceCalendarPlusAndroidPlugin(
        newProviderExecutor = { java.util.concurrent.Executor(providerQueue::addLast) },
        postToMain = { block -> block() },
    ).apply {
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

    /**
     * A modal the plugin is already waiting on, as if its launch succeeded.
     * Seeded through pendingModal because a real launch builds an
     * android.content.Intent, which plain JVM tests don't have — don't swap
     * this for an Intent mock. The assertions go through the public paths.
     */
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

        assertTrue(plugin.onActivityResult(showCode, Activity.RESULT_OK, null))
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
    fun onDetachedFromActivityForConfigChanges_carriesThePendingReplyToTheRecreatedActivity() {
        val first = showingModal(showCode)

        plugin.onDetachedFromActivityForConfigChanges()
        plugin.onReattachedToActivityForConfigChanges(activityBinding())
        assertTrue(plugin.onActivityResult(showCode, Activity.RESULT_CANCELED, null))

        assertEquals(listOf("success(null)"), first.replies)
    }

    // No activity will ever deliver the result, so resolve rather than hang.
    @Test
    fun onDetachedFromActivity_resolvesThePendingReply() {
        val first = showingModal(createCode)

        plugin.onDetachedFromActivity()

        assertEquals(listOf("success(null)"), first.replies)
    }

    @Test
    fun onActivityResult_forTheOtherModal_leavesThePendingReply() {
        val first = showingModal(showCode)

        // Not ours to consume: it's left for other listeners.
        assertFalse(plugin.onActivityResult(createCode, Activity.RESULT_OK, null))

        assertEquals(emptyList(), first.replies)
    }

    // The detach resolves the claimed reply while the event lookup is still
    // on the provider thread. The lookup's outcome must not reply again, nor
    // touch a modal that claimed the freed slot in the meantime.
    @Test
    fun showEventModal_activityDetachedDuringLookup_repliesOnce() {
        plugin.onAttachedToActivity(activityBinding())
        val result = call("showEventModal", mapOf("eventId" to "1"))

        plugin.onDetachedFromActivity()
        val next = showingModal(createCode)
        runProviderWork()

        assertEquals(listOf("success(null)"), result.replies)
        assertEquals(emptyList(), next.replies)
    }
}
