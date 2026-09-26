package to.bullet.device_calendar_plus_android

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.CalendarContract

/**
 * Selects an event row by `_ID`, skipping DELETED=1 tombstones. A tombstone
 * is what a non-sync-adapter delete leaves on an event with a `_sync_id` — a
 * synced calendar's, or a local series the plugin has keyed (see
 * [SeriesRowStore.ensureLocalSeriesSyncId]). Instances queries already skip
 * it, so [EventsService.getEvent] and [SeriesRowStore.readEventRow] read it
 * as gone too: otherwise an edit or a per-occurrence delete would write
 * against a row that never shows in a listing.
 */
internal val liveEventById =
    "${CalendarContract.Events._ID} = ? AND ${CalendarContract.Events.DELETED} = 0"

/**
 * The account a calendar belongs to. [isLocal] means no sync adapter
 * will ever touch its rows, so columns the provider reserves for one
 * (`_sync_id`, say) are the plugin's to manage.
 */
internal data class CalendarAccount(val name: String, val type: String) {
    val isLocal: Boolean get() = type == CalendarContract.ACCOUNT_TYPE_LOCAL
}

/**
 * The [CalendarAccount] of the Events row under the cursor, from its
 * ACCOUNT_NAME and ACCOUNT_TYPE columns. The provider guarantees both
 * on every calendar, so a NULL is a broken invariant and throws rather
 * than standing in a made-up value — the one policy for the account
 * columns, wherever they are read off a row. ([SeriesRowStore.readEventRow]'s
 * other non-null columns keep their older fallbacks.)
 */
internal fun Cursor.calendarAccount(): CalendarAccount {
    fun str(column: String): String =
        checkNotNull(getString(getColumnIndexOrThrow(column))) {
            "Events row has no $column"
        }
    return CalendarAccount(
        name = str(CalendarContract.Events.ACCOUNT_NAME),
        type = str(CalendarContract.Events.ACCOUNT_TYPE)
    )
}

/**
 * A live master row from the Events view. [account] is the calendar's,
 * which the view joins in: [SeriesRowStore.deleteUri] and
 * [SeriesRowStore.ensureLocalSeriesSyncId] build their local-calendar
 * sync-adapter URIs from it, without a second query.
 */
internal data class EventRow(
    val id: String,
    val calendarId: String,
    val account: CalendarAccount,
    val title: String,
    val description: String?,
    val location: String?,
    val url: String?,
    val dtstart: Long,
    val dtend: Long?,
    val duration: String?,
    val allDay: Boolean,
    val timeZone: String?,
    val availability: String,
    val rrule: String?,
    val syncId: String?
)

/**
 * A master [row] proven recurring: its [rrule] is the row's, non-null.
 * The type is what the series writers — [EventsService]'s exception insert
 * and [SeriesRowStore.ensureLocalSeriesSyncId] — take, so a one-off event's
 * row cannot reach them.
 */
internal data class SeriesRow(val row: EventRow, val rrule: String)

/**
 * This master row as a [SeriesRow]: INVALID_ARGUMENTS when it is not
 * recurring, since a one-off event has no occurrence apart from itself.
 */
internal fun EventRow.asSeries(): Result<SeriesRow> {
    val rrule = this.rrule
        ?: return Result.failure(
            CalendarException(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "Event $id is not recurring, so it has no single occurrence " +
                    "to address; edit or delete the event itself instead"
            )
        )
    return Result.success(SeriesRow(this, rrule))
}

/**
 * The Events-table reads and writes behind every series edit: reading a
 * master row, keying a local series, rewriting a series so the provider
 * re-expands it, the update-by-ID, and the URIs and selections its deletes
 * go through. [EventsService] and [DetachedOccurrenceCarry] both write
 * through here, so a split's truncate and its carry take the same paths.
 *
 * Reads [Context.getContentResolver] per call, as the service does, so
 * constructing one touches nothing.
 */
internal class SeriesRowStore(private val context: Context) {

    val resolver: ContentResolver get() = context.contentResolver

    /**
     * Reads the master row of an event straight from the Events table:
     * NOT_FOUND when the event is missing (or a DELETED tombstone).
     */
    fun readEventRow(eventId: String): Result<EventRow> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CALENDAR_ID,
            CalendarContract.Events.ACCOUNT_NAME,
            CalendarContract.Events.ACCOUNT_TYPE,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.CUSTOM_APP_URI,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.DURATION,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.EVENT_TIMEZONE,
            CalendarContract.Events.AVAILABILITY,
            CalendarContract.Events.RRULE,
            CalendarContract.Events._SYNC_ID
        )
        resolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            liveEventById,
            arrayOf(eventId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use
            return Result.success(EventRow(
                id = cursor.stringOrNull(CalendarContract.Events._ID) ?: eventId,
                calendarId = cursor.stringOrNull(CalendarContract.Events.CALENDAR_ID) ?: "",
                account = cursor.calendarAccount(),
                title = cursor.stringOrNull(CalendarContract.Events.TITLE) ?: "",
                description = cursor.stringOrNull(CalendarContract.Events.DESCRIPTION),
                location = cursor.stringOrNull(CalendarContract.Events.EVENT_LOCATION),
                url = cursor.stringOrNull(CalendarContract.Events.CUSTOM_APP_URI),
                dtstart = cursor.longOrNull(CalendarContract.Events.DTSTART) ?: 0L,
                dtend = cursor.longOrNull(CalendarContract.Events.DTEND),
                duration = cursor.stringOrNull(CalendarContract.Events.DURATION),
                allDay = (cursor.longOrNull(CalendarContract.Events.ALL_DAY) ?: 0L) == 1L,
                timeZone = cursor.stringOrNull(CalendarContract.Events.EVENT_TIMEZONE),
                availability = availabilityToString(
                    cursor.longOrNull(CalendarContract.Events.AVAILABILITY)?.toInt()
                ),
                rrule = cursor.stringOrNull(CalendarContract.Events.RRULE),
                syncId = cursor.stringOrNull(CalendarContract.Events._SYNC_ID)
            ))
        }
        return Result.failure(
            CalendarException(
                PlatformExceptionCodes.NOT_FOUND,
                "Event with ID $eventId not found"
            )
        )
    }

    /**
     * The master row a per-occurrence call addresses — an exception write in
     * [EventsService.updateEventInstance] and [EventsService.deleteEventInstance],
     * the split in [EventsService.deleteRecurringThisAndFollowing], the new
     * series that [DetachedOccurrenceCarry] keys. NOT_FOUND when the event is
     * missing (or a DELETED tombstone), then [asSeries]. The split in
     * [EventsService.updateRecurringThisAndFollowing] takes that second step
     * alone, on the row [EventsService.updateRecurring] already read.
     */
    fun readRecurringRow(eventId: String): Result<SeriesRow> {
        val row = readEventRow(eventId).getOrElse { return Result.failure(it) }
        return row.asSeries()
    }

    /**
     * Gives a recurring series on a local calendar a `_sync_id` before an
     * exception is written against it. The Calendar Provider keys a series'
     * exceptions by `_sync_id` / `original_sync_id`; without one, the
     * exception insert drops the master's own occurrences from the Instances
     * cache (#153).
     *
     * Only local calendars are touched: nothing else will ever assign them a
     * `_sync_id`, whereas a synced calendar's adapter owns that column. The
     * write goes as a sync adapter (the column is read-only otherwise).
     *
     * The trade: the provider physically deletes an event only for a sync
     * adapter or when `_sync_id` is empty, so once a local series carries
     * one, a delete by a non-sync-adapter caller (the stock Calendar app,
     * say) leaves it as a DELETED=1 row that no adapter will ever collect.
     * Instances queries skip such rows, [EventsService.getEvent] and
     * [readEventRow] filter them out, and the plugin's own deletes go through
     * [deleteUri] as the stand-in adapter, which removes them.
     *
     * Exceptions already written against the series before it had an id — by
     * an older plugin version or another app — join the family with this one
     * write: the provider's `original_sync_update` trigger (in AOSP's
     * CalendarDatabaseHelper since database version 301, Android 4.0) copies
     * a changed `_sync_id` into the `original_sync_id` of every row whose
     * `original_id` is this master. That is an upgrade-only path: the id is
     * now assigned before the first exception write, so the public API can no
     * longer produce a keyless series with exceptions.
     *
     * Fails with OPERATION_FAILED when the provider refuses the key write —
     * matching no row, whatever the reason — so the caller never writes an
     * exception against a master that is still keyless, which is the very
     * write #153 comes from. A master that vanished between the caller's
     * read and now lands here too: the exception insert would throw on the
     * missing original anyway, and the outer catch maps that to
     * OPERATION_FAILED as well.
     *
     * Returns the series' key: the one it had, the one just assigned, or
     * null on a synced calendar whose adapter has not keyed it yet.
     */
    fun ensureLocalSeriesSyncId(series: SeriesRow): Result<String?> {
        val row = series.row
        if (row.syncId != null) return Result.success(row.syncId)
        if (!row.account.isLocal) return Result.success(null)

        val syncId = "device_calendar_plus:${java.util.UUID.randomUUID()}"
        val updated = resolver.update(
            syncAdapterUri(CalendarContract.Events.CONTENT_URI, row.account),
            ContentValues().apply {
                put(CalendarContract.Events._SYNC_ID, syncId)
            },
            "${CalendarContract.Events._ID} = ?",
            arrayOf(row.id)
        )
        if (updated == 0) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Could not key series ${row.id} before writing its exception"
                )
            )
        }
        return Result.success(syncId)
    }

    /**
     * Writes series row [row]'s [rrule] together with its time columns (its
     * DTSTART, and its DURATION when it has one), so the provider re-expands
     * its Instances. Returns the rows updated.
     *
     * Android's CalendarProvider doesn't always invalidate the Instances
     * cache when only RRULE changes, and not at all when a series gains
     * exceptions by an update to their rows rather than an exception insert:
     * the row on disk is right while listEvents keeps returning the old
     * expansion. Touching the time columns too, even with their existing
     * values, forces it to regenerate. Every series write that has to show
     * in the next listing — a truncate, a re-parent, or an exception insert
     * against a synced series its adapter has not keyed yet (#163) — goes
     * through here.
     */
    fun rewriteSeriesForReexpand(row: EventRow, rrule: String): Int =
        updateEventRow(row.id, ContentValues().apply {
            put(CalendarContract.Events.RRULE, rrule)
            put(CalendarContract.Events.DTSTART, row.dtstart)
            if (row.duration != null) {
                put(CalendarContract.Events.DURATION, row.duration)
            }
        })

    /**
     * Updates event row [eventId] with [values]: the one update-by-ID in
     * the plugin. A plain caller's write on every account, so on a synced
     * calendar the provider marks the row DIRTY and the adapter uploads the
     * change (#132). Returns the rows updated.
     *
     * The series writers send RRULE, DTSTART and DURATION this way. A
     * plain update keeps them all: the provider throws on the sync
     * columns a plain caller may not set, and RRULE is not one of them.
     * (An earlier version wrote as the sync adapter on the belief that
     * RRULE was stripped otherwise; it was the missing DELETED filter on
     * the plugin's own reads, since added, that made deletes look like
     * they had not taken.)
     */
    fun updateEventRow(eventId: String, values: ContentValues): Int =
        resolver.update(
            CalendarContract.Events.CONTENT_URI,
            values,
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId)
        )

    /**
     * The Events URI the plugin's deletes against [account]'s rows go to:
     * plain, or with sync-adapter context when the account is local.
     *
     * A plain delete tombstones a row that carries a `_sync_id` (DELETED=1,
     * DIRTY=1) instead of removing it. On a synced calendar that is the
     * point: the adapter uploads the tombstone and then collects it,
     * whereas a delete written as the adapter is taken as the server's own
     * word, never uploaded, and the next sync brings the event back
     * (#132). On a local calendar no adapter will ever collect it, and a
     * local row can carry a key ([ensureLocalSeriesSyncId] gives a series
     * one before its first exception; some providers key every row), so
     * the delete goes as the stand-in adapter, which removes the row.
     *
     * That key write and these deletes are the only event writes in the
     * plugin that borrow the adapter's context; every other event write is
     * the plain caller's on every account.
     */
    fun deleteUri(account: CalendarAccount): Uri =
        if (account.isLocal) syncAdapterUri(CalendarContract.Events.CONTENT_URI, account)
        else CalendarContract.Events.CONTENT_URI

    /**
     * Removes the detached occurrences of [master] whose original slot is
     * at or after [fromInstant]: the second half of a `thisAndFollowing`
     * delete, and of an update split whose new event doesn't recur.
     *
     * Truncating the master's rule only stops it generating occurrences. An
     * occurrence that was edited on its own is a detached exception row
     * (ORIGINAL_ID = master, ORIGINAL_INSTANCE_TIME = the instant it
     * replaced), so one past the split would survive as an orphan: out of
     * the Instances cache the truncate rebuilds, but still on disk, and back
     * in listEvents once the provider next regenerates it. iOS's
     * EKSpan.futureEvents removes those too, so Android matches it.
     *
     * Which rows go is [detachedFrom]'s slot rule. Deletes through
     * [deleteUri] for the master's account: tombstoned for the adapter to
     * upload on a synced calendar, removed on a local one.
     */
    fun deleteDetachedOccurrencesFrom(master: EventRow, fromInstant: Long) {
        val (selection, args) = detachedFrom(master, fromInstant)
        resolver.delete(deleteUri(master.account), selection, args)
    }

    /**
     * The selection, and its arguments, for the detached occurrences of
     * [master] whose original slot is at or after [fromInstant]: the rows a
     * `thisAndFollowing` split sweeps or carries. The slot the exception
     * replaced decides, not where it was moved to: an occurrence dragged
     * from before the split to after it stays with the old series, and one
     * dragged from after the split to before it goes with the split.
     */
    fun detachedFrom(master: EventRow, fromInstant: Long): Pair<String, Array<String>> =
        "${CalendarContract.Events.ORIGINAL_ID} = ? AND " +
            "${CalendarContract.Events.ORIGINAL_INSTANCE_TIME} >= ?" to
            arrayOf(master.id, fromInstant.toString())

    /** [base] (an Events URI) with sync-adapter context for [account]. */
    private fun syncAdapterUri(base: Uri, account: CalendarAccount): Uri =
        base.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_NAME, account.name)
            .appendQueryParameter(CalendarContract.Events.ACCOUNT_TYPE, account.type)
            .build()
}
