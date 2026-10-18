package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract
import io.flutter.plugin.common.MethodCall

/**
 * The field edits of an event update — title, description, location, url,
 * all-day flag, time zone and availability, plus the Android-only status
 * and attendees.
 * Null fields are left untouched; fields named in [clearedFields] are
 * cleared.
 *
 * Shared by [EventsService.updateEvent] and [EventsService.updateRecurring],
 * whose remaining parameters are the ones that differ per operation.
 */
data class EventFieldPatch(
    val title: String?,
    val description: String?,
    val location: String?,
    val url: String?,
    val isAllDay: Boolean?,
    val timeZone: String?,
    val availability: String?,
    /** The reminders edit, as minutes before the start. */
    val reminders: RowsPatch<Int>,
    /**
     * The new [CalendarContract.Events.STATUS], or null to leave it. There
     * is no clear: the provider throws on a NULL STATUS in an update.
     */
    val status: Int?,
    /** The Android-only attendees edit (see [keeps]). */
    val attendees: RowsPatch<AttendeeRow>,
    val clearedFields: List<String>
) {
    companion object {
        /** Reads the patch fields from a method-channel [call]. */
        fun fromCall(call: MethodCall): EventFieldPatch {
            val clearedFields = call.argument<List<String>>("clearedFields") ?: emptyList()
            return EventFieldPatch(
                title = call.argument<String>("title"),
                description = call.argument<String>("description"),
                location = call.argument<String>("location"),
                url = call.argument<String>("url"),
                isAllDay = call.argument<Boolean>("isAllDay"),
                timeZone = call.argument<String>("timeZone"),
                availability = call.argument<String>("availability"),
                reminders = call.rowsPatch("reminders", clearedFields) { list ->
                    list.map { it as Int }
                },
                status = call.statusArg(),
                attendees = call.rowsPatch("attendees", clearedFields) { list ->
                    list.map { attendeeRowFromArg(it as Map<*, *>) }
                },
                clearedFields = clearedFields
            )
        }
    }
}

/**
 * The three states of an edit to an event's child rows (reminders,
 * attendees): leave them untouched, replace the whole set, or remove them
 * all. Mirrors the Dart `Patch<List<…>>` over the method channel.
 */
sealed class RowsPatch<out T> {
    object Unchanged : RowsPatch<Nothing>()
    data class Set<T>(val rows: List<T>) : RowsPatch<T>()
    object Clear : RowsPatch<Nothing>()
}

/**
 * Reads a child-rows edit from the call's [key]: a present key sets (its
 * list run through [parse]), the key named in [clearedFields] clears,
 * neither leaves the rows unchanged.
 */
internal fun <T> MethodCall.rowsPatch(
    key: String,
    clearedFields: List<String>,
    parse: (List<*>) -> List<T>
): RowsPatch<T> {
    val rows = argument<List<*>>(key)
    return when {
        rows != null -> RowsPatch.Set(parse(rows))
        key in clearedFields -> RowsPatch.Clear
        else -> RowsPatch.Unchanged
    }
}
