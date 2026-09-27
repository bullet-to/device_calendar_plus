package to.bullet.device_calendar_plus_android

import io.flutter.plugin.common.MethodChannel.Result

/**
 * The reply for the one native modal that's showing (#123).
 *
 * The modal endpoints complete when the calendar activity returns, so their
 * channel reply is held here until [complete]. Every path out of the slot
 * replies exactly once — a reply that's dropped leaves the Dart `await`
 * hanging forever.
 *
 * One modal at a time, across both kinds: a second call while one is showing
 * fails with OPERATION_FAILED rather than overwriting (and so orphaning) the
 * first reply. iOS can only present one modal from a view controller, so this
 * is the same rule on both platforms.
 */
internal class PendingModal {
    private var result: Result? = null
    private var requestCode: Int? = null

    /**
     * Claims the slot for a modal launched with [requestCode]. When one is
     * already showing, replies OPERATION_FAILED to [result] and returns false.
     */
    fun begin(requestCode: Int, result: Result): Boolean {
        if (this.result != null) {
            result.error(
                PlatformExceptionCodes.OPERATION_FAILED,
                "A calendar modal is already showing",
                null
            )
            return false
        }
        this.result = result
        this.requestCode = requestCode
        return true
    }

    /**
     * The modal launched with [requestCode] closed: reply and free the slot.
     * False when the slot holds no such modal.
     */
    fun complete(requestCode: Int): Boolean {
        if (this.requestCode != requestCode) return false
        take()?.success(null)
        return true
    }

    /** The launch failed: reply with the error and free the slot. */
    fun fail(code: String, message: String?) {
        take()?.error(code, message, null)
    }

    /**
     * The activity is gone for good (not a config change — that recreates
     * the activity, which then receives the result). Nothing will deliver the
     * modal's result now, so resolve it as closed rather than hang.
     */
    fun activityGone() {
        take()?.success(null)
    }

    private fun take(): Result? {
        val pending = result
        result = null
        requestCode = null
        return pending
    }
}
