package to.bullet.device_calendar_plus_android

import android.content.ContentValues
import android.provider.CalendarContract
import io.flutter.plugin.common.MethodCall

// Both directions of the CalendarContract.Events.STATUS column: the read
// side's `Event.status` name, and the write side's `EventStatusAndroid` name
// and insert-row value.

// A NULL STATUS column means "no status", not 0 — and 0 is
// STATUS_TENTATIVE, so defaulting the column would invent a status.
internal fun statusToString(status: Int?): String {
    return when (status) {
        CalendarContract.Events.STATUS_CONFIRMED -> "confirmed"
        CalendarContract.Events.STATUS_TENTATIVE -> "tentative"
        CalendarContract.Events.STATUS_CANCELED -> "canceled"
        else -> "none"
    }
}

/**
 * The [CalendarContract.Events.STATUS] value for an `EventStatusAndroid`
 * name from the method channel — Android's own value set, written as it is.
 * An unknown name breaks the channel contract (the Dart enum sends only these
 * three) and throws.
 */
internal fun eventStatusFromName(name: String): Int = when (name) {
    "tentative" -> CalendarContract.Events.STATUS_TENTATIVE
    "confirmed" -> CalendarContract.Events.STATUS_CONFIRMED
    "canceled" -> CalendarContract.Events.STATUS_CANCELED
    else -> throw IllegalArgumentException("Unknown event status: $name")
}

/** The call's `status` argument as a STATUS value, or null when absent. */
internal fun MethodCall.statusArg(): Int? =
    argument<String>("status")?.let(::eventStatusFromName)

/**
 * Puts [status] as the STATUS column of a row these values insert, NULL
 * included: a row copied from one with no status gets none. An insert takes
 * a NULL; an update can't (see [EventFieldPatch.status]).
 */
internal fun ContentValues.putStatus(status: Int?) {
    if (status != null) {
        put(CalendarContract.Events.STATUS, status)
    } else {
        putNull(CalendarContract.Events.STATUS)
    }
}
