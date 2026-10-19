package to.bullet.device_calendar_plus_android

import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.ContentValues
import android.provider.CalendarContract.Reminders

// CalendarContract.Reminders as the plugin writes it: one relative
// METHOD_ALERT row per minute value, that many minutes before the start;
// and the raw rows a `thisAndFollowing` split carries as stored.

/**
 * Event [eventId]'s Reminders rows, whatever the method, as insert values
 * without their EVENT_ID: MINUTES and METHOD copied as stored (nulls
 * included).
 */
internal fun ContentResolver.readReminderRows(eventId: Long): List<ContentValues> {
    val columns = arrayOf(Reminders.MINUTES, Reminders.METHOD)
    val rows = mutableListOf<ContentValues>()
    query(
        Reminders.CONTENT_URI,
        columns,
        "${Reminders.EVENT_ID} = ?",
        arrayOf(eventId.toString()),
        null
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            rows += ContentValues().apply { cursor.copyColumnsInto(this, columns) }
        }
    }
    return rows
}

/**
 * Inserts of raw Reminders [rows] (from [readReminderRows]) as they are,
 * METHOD included, unlike [reminderInsertOps], which writes METHOD_ALERT.
 * [keyToEvent] sets each row's EVENT_ID, as for [reminderInsertOps].
 */
internal fun reminderRowInsertOps(
    rows: List<ContentValues>,
    keyToEvent: ContentProviderOperation.Builder.() -> ContentProviderOperation.Builder
): List<ContentProviderOperation> = rows.map { row ->
    ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
        .withValues(row)
        .keyToEvent()
        .build()
}

/**
 * Inserts of one Reminders row per value of [minutes], the one builder of
 * every reminder insert the plugin makes from minutes. [keyToEvent] sets
 * each row's EVENT_ID: a fixed ID (`withValue`) or a back-reference to an
 * event insert earlier in the same batch (`withValueBackReference`).
 */
internal fun reminderInsertOps(
    minutes: List<Int>,
    keyToEvent: ContentProviderOperation.Builder.() -> ContentProviderOperation.Builder
): List<ContentProviderOperation> = minutes.map { m ->
    ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
        .withValue(Reminders.MINUTES, m)
        .withValue(Reminders.METHOD, Reminders.METHOD_ALERT)
        .keyToEvent()
        .build()
}

/**
 * The operations that apply [patch] to event [eventId]'s Reminders rows: a
 * set deletes them all and inserts its own, a clear deletes them all,
 * unchanged needs none.
 */
internal fun remindersPatchOps(
    eventId: Long,
    patch: RowsPatch<Int>
): List<ContentProviderOperation> {
    if (patch == RowsPatch.Unchanged) return emptyList()
    val deleteAll = ContentProviderOperation.newDelete(Reminders.CONTENT_URI)
        .withSelection("${Reminders.EVENT_ID} = ?", arrayOf(eventId.toString()))
        .build()
    val inserts = (patch as? RowsPatch.Set)?.rows
        ?.let { minutes -> reminderInsertOps(minutes) { withValue(Reminders.EVENT_ID, eventId) } }
        ?: emptyList()
    return listOf(deleteAll) + inserts
}
