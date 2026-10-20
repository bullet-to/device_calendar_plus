package to.bullet.device_calendar_plus_android

import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.provider.CalendarContract.Attendees
import io.flutter.plugin.common.MethodCall

// CalendarContract.Attendees as the plugin reads and writes it: every read
// and insert of its rows, and `AttendeeWriteAndroid` from the method channel,
// Android's own columns and value sets written as they are (#71). iOS
// can't write attendees, so nothing here is mapped onto the shared,
// read-only `Attendee`; AttendeeReads.kt does that for EventsService's reads.

/**
 * One [Attendees] row as the plugin writes or carries it, each column as
 * stored (null when NULL). [identity] and [idNamespace] are never written
 * from the channel; they ride along when a `thisAndFollowing` split copies
 * the original series' rows.
 */
data class AttendeeRow(
    val email: String?,
    val name: String?,
    val type: Int?,
    val relationship: Int?,
    val status: Int?,
    val identity: String? = null,
    val idNamespace: String? = null
) {
    /** Whether this is the event's organizer row, which reads skip. */
    val isOrganizer: Boolean get() = relationship == Attendees.RELATIONSHIP_ORGANIZER

    /** The row as insert values, nulls included, without its EVENT_ID. */
    fun toValues(): ContentValues = ContentValues().apply {
        put(Attendees.ATTENDEE_EMAIL, email)
        put(Attendees.ATTENDEE_NAME, name)
        put(Attendees.ATTENDEE_TYPE, type)
        put(Attendees.ATTENDEE_RELATIONSHIP, relationship)
        put(Attendees.ATTENDEE_STATUS, status)
        put(Attendees.ATTENDEE_IDENTITY, identity)
        put(Attendees.ATTENDEE_ID_NAMESPACE, idNamespace)
    }
}

/**
 * Whether existing [row] survives this attendees edit.
 *
 * A set or a clear spares the organizer row (RELATIONSHIP_ORGANIZER), which
 * the plugin's reads skip, so the event keeps its organizer; a set whose
 * list holds an organizer replaces that row too.
 */
internal fun RowsPatch<AttendeeRow>.keeps(row: AttendeeRow): Boolean = when (this) {
    RowsPatch.Unchanged -> true
    RowsPatch.Clear -> row.isOrganizer
    is RowsPatch.Set -> row.isOrganizer && rows.none { it.isOrganizer }
}

/** The rows an event holding [existing] holds after this attendees edit. */
internal fun RowsPatch<AttendeeRow>.applyTo(existing: Collection<AttendeeRow>): List<AttendeeRow> =
    existing.filter(::keeps) + ((this as? RowsPatch.Set)?.rows ?: emptyList())

/**
 * The [Attendees.ATTENDEE_TYPE] value for an `AttendeeTypeAndroid` name. An
 * unknown name breaks the channel contract and throws.
 */
internal fun attendeeTypeFromName(name: String): Int = when (name) {
    "none" -> Attendees.TYPE_NONE
    "required" -> Attendees.TYPE_REQUIRED
    "optional" -> Attendees.TYPE_OPTIONAL
    "resource" -> Attendees.TYPE_RESOURCE
    else -> throw IllegalArgumentException("Unknown attendee type: $name")
}

/**
 * The [Attendees.ATTENDEE_RELATIONSHIP] value for an
 * `AttendeeRelationshipAndroid` name. An unknown name throws.
 */
internal fun attendeeRelationshipFromName(name: String): Int = when (name) {
    "none" -> Attendees.RELATIONSHIP_NONE
    "attendee" -> Attendees.RELATIONSHIP_ATTENDEE
    "organizer" -> Attendees.RELATIONSHIP_ORGANIZER
    "performer" -> Attendees.RELATIONSHIP_PERFORMER
    "speaker" -> Attendees.RELATIONSHIP_SPEAKER
    else -> throw IllegalArgumentException("Unknown attendee relationship: $name")
}

/**
 * The [Attendees.ATTENDEE_STATUS] value for an `AttendeeStatusAndroid`
 * name. An unknown name throws.
 */
internal fun attendeeStatusFromName(name: String): Int = when (name) {
    "none" -> Attendees.ATTENDEE_STATUS_NONE
    "accepted" -> Attendees.ATTENDEE_STATUS_ACCEPTED
    "declined" -> Attendees.ATTENDEE_STATUS_DECLINED
    "invited" -> Attendees.ATTENDEE_STATUS_INVITED
    "tentative" -> Attendees.ATTENDEE_STATUS_TENTATIVE
    else -> throw IllegalArgumentException("Unknown attendee status: $name")
}

/** One `AttendeeWriteAndroid` from the method channel as the row it writes. */
internal fun attendeeRowFromArg(arg: Map<*, *>): AttendeeRow = AttendeeRow(
    email = arg["email"] as String,
    name = arg["name"] as String?,
    type = attendeeTypeFromName(arg["type"] as String),
    relationship = attendeeRelationshipFromName(arg["relationship"] as String),
    status = attendeeStatusFromName(arg["status"] as String)
)

/** The call's `attendees` argument as rows, or null when absent. */
internal fun MethodCall.attendeesArg(): List<AttendeeRow>? =
    argument<List<Map<*, *>>>("attendees")?.map(::attendeeRowFromArg)

/**
 * Inserts of [rows] as Attendees rows, the one builder of every Attendees
 * insert the plugin makes. [keyToEvent] sets each row's EVENT_ID: a fixed
 * ID (`withValue`) or a back-reference to an event insert earlier in the
 * same batch (`withValueBackReference`).
 */
internal fun attendeeInsertOps(
    rows: Collection<AttendeeRow>,
    keyToEvent: ContentProviderOperation.Builder.() -> ContentProviderOperation.Builder
): List<ContentProviderOperation> = rows.map { row ->
    ContentProviderOperation.newInsert(Attendees.CONTENT_URI)
        .withValues(row.toValues())
        .keyToEvent()
        .build()
}

/**
 * Event [eventId]'s Attendees rows, organizer included, by their own `_ID`,
 * in the provider's order.
 */
internal fun ContentResolver.readAttendeeRows(eventId: Long): Map<Long, AttendeeRow> {
    val rows = linkedMapOf<Long, AttendeeRow>()
    query(
        Attendees.CONTENT_URI,
        arrayOf(
            Attendees._ID,
            Attendees.ATTENDEE_EMAIL,
            Attendees.ATTENDEE_NAME,
            Attendees.ATTENDEE_TYPE,
            Attendees.ATTENDEE_RELATIONSHIP,
            Attendees.ATTENDEE_STATUS,
            Attendees.ATTENDEE_IDENTITY,
            Attendees.ATTENDEE_ID_NAMESPACE
        ),
        "${Attendees.EVENT_ID} = ?",
        arrayOf(eventId.toString()),
        null
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            rows[cursor.getLong(cursor.getColumnIndexOrThrow(Attendees._ID))] = AttendeeRow(
                email = cursor.stringOrNull(Attendees.ATTENDEE_EMAIL),
                name = cursor.stringOrNull(Attendees.ATTENDEE_NAME),
                type = cursor.longOrNull(Attendees.ATTENDEE_TYPE)?.toInt(),
                relationship = cursor.longOrNull(Attendees.ATTENDEE_RELATIONSHIP)?.toInt(),
                status = cursor.longOrNull(Attendees.ATTENDEE_STATUS)?.toInt(),
                identity = cursor.stringOrNull(Attendees.ATTENDEE_IDENTITY),
                idNamespace = cursor.stringOrNull(Attendees.ATTENDEE_ID_NAMESPACE)
            )
        }
    }
    return rows
}

/**
 * The operations that apply [patch] to event [eventId]'s Attendees rows:
 * deletes of the rows it doesn't keep, then inserts of a set's rows.
 * Unchanged needs none and reads nothing.
 */
internal fun ContentResolver.attendeesPatchOps(
    eventId: Long,
    patch: RowsPatch<AttendeeRow>
): List<ContentProviderOperation> {
    if (patch == RowsPatch.Unchanged) return emptyList()
    val ops = mutableListOf<ContentProviderOperation>()
    for ((id, row) in readAttendeeRows(eventId)) {
        if (patch.keeps(row)) continue
        // By the row's own URI: the provider joins Attendees with Events
        // for a selection, so a bare `_id` there is ambiguous.
        ops += ContentProviderOperation
            .newDelete(ContentUris.withAppendedId(Attendees.CONTENT_URI, id))
            .build()
    }
    if (patch is RowsPatch.Set) {
        ops += attendeeInsertOps(patch.rows) { withValue(Attendees.EVENT_ID, eventId) }
    }
    return ops
}
