package to.bullet.device_calendar_plus_android

import io.flutter.plugin.common.MethodCall

/**
 * The shared field edits of an event update — title, description, location,
 * url, all-day flag, time zone and availability. Null fields are left
 * untouched; fields named in [clearedFields] are cleared.
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
    val clearedFields: List<String>
) {
    companion object {
        /** Reads the patch fields from a method-channel [call]. */
        fun fromCall(call: MethodCall) = EventFieldPatch(
            title = call.argument<String>("title"),
            description = call.argument<String>("description"),
            location = call.argument<String>("location"),
            url = call.argument<String>("url"),
            isAllDay = call.argument<Boolean>("isAllDay"),
            timeZone = call.argument<String>("timeZone"),
            availability = call.argument<String>("availability"),
            clearedFields = call.argument<List<String>>("clearedFields") ?: emptyList()
        )
    }
}
