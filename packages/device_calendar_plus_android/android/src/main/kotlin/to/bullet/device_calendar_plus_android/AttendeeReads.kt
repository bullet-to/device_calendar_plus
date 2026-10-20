package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees

// CalendarContract.Attendees rows read out to the shared, read-only model:
// `Event.attendees` and `Event.organizer`. AttendeeRows.kt reads and writes
// the rows themselves in Android's own terms; everything mapped onto the
// shared model lives here (#236).

/**
 * [rows] as shared `Attendee` maps, the organizer row left out. Blank names
 * and emails pass through unchanged on purpose, as they always have (and as
 * iOS attendees do); only [organizerOf] drops them.
 */
internal fun attendeeMaps(rows: Collection<AttendeeRow>): List<Map<String, Any?>> =
    rows.filterNot { it.isOrganizer }
        .map { row ->
            // A NULL type or status reads as 0, as Cursor.getInt has it.
            mapOf(
                "name" to row.name,
                "emailAddress" to row.email,
                "role" to attendeeTypeToRole(row.type ?: 0),
                "status" to attendeeStatusToString(row.status ?: 0),
            )
        }

/**
 * The shared `Organizer` map for an event holding attendee [rows] and the
 * Events.ORGANIZER value [eventOrganizer], or null when it has none; the
 * full contract is on Dart's `Event.organizer`.
 *
 * The organizer row (RELATIONSHIP_ORGANIZER) wins when it holds a non-blank
 * name or email, and [eventOrganizer] is never merged into it (it can be a
 * different person). Otherwise [eventOrganizer] stands in as the email alone.
 * No [rows] at all means no organizer.
 */
internal fun organizerOf(rows: Collection<AttendeeRow>, eventOrganizer: String?): Map<String, String>? {
    if (rows.isEmpty()) return null
    val row = rows.firstOrNull { it.isOrganizer }
    val name = row?.name?.takeUnless { it.isBlank() }
    val email = row?.email?.takeUnless { it.isBlank() }
    if (name != null || email != null) {
        return buildMap {
            name?.let { put("name", it) }
            email?.let { put("emailAddress", it) }
        }
    }
    return eventOrganizer?.takeUnless { it.isBlank() }?.let { mapOf("emailAddress" to it) }
}

/** An ATTENDEE_TYPE as the shared `AttendeeRole` name. */
private fun attendeeTypeToRole(type: Int): String = when (type) {
    Attendees.TYPE_REQUIRED -> "required"
    Attendees.TYPE_OPTIONAL -> "optional"
    Attendees.TYPE_RESOURCE -> "nonParticipant"
    else -> "required"
}

/** An ATTENDEE_STATUS as the shared `AttendeeStatus` name. */
private fun attendeeStatusToString(status: Int): String = when (status) {
    Attendees.ATTENDEE_STATUS_ACCEPTED -> "accepted"
    Attendees.ATTENDEE_STATUS_DECLINED -> "declined"
    Attendees.ATTENDEE_STATUS_TENTATIVE -> "tentative"
    Attendees.ATTENDEE_STATUS_INVITED -> "pending"
    else -> "none"
}
