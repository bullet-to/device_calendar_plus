package to.bullet.device_calendar_plus_android

import android.content.ContentProviderOperation
import android.content.ContentValues
import android.net.Uri
import android.provider.CalendarContract

/**
 * Settles the detached occurrences past a `thisAndFollowing` update split:
 * the second half of [EventsService.updateRecurring]'s split, and its
 * counterpart to the delete path's sweep of the same rows (#158).
 *
 * iOS's EKSpan.futureEvents save re-parents them: each keeps its own
 * edits (title, moved time), and the new series skips its slot instead
 * of generating a second occurrence beside it. Left keyed to the old
 * master, Android would list both.
 *
 * Writes through [store], the same series-row paths as every other
 * series write.
 */
internal class DetachedOccurrenceCarry(private val store: SeriesRowStore) {

    private val resolver get() = store.resolver

    /**
     * Carries the detached occurrences of [master] whose original slot is
     * at or after [fromInstant] onto the series [newMasterId], or removes
     * them when the new event doesn't recur.
     *
     * Each carried occurrence and its slot move as [shift] says, because
     * the new series generates every slot moved by the split; iOS keeps the
     * pairing across the move, and moves the occurrence itself by the same
     * whole days, so Android does too. The same slot rule as the delete
     * path decides which rows carry over: where each occurrence was, not
     * where it was moved to. A deleted occurrence is the exception: iOS
     * keeps its deleted date at the old time, so it carries over only when
     * the split leaves its slot where it was.
     *
     * How a row carries over depends on the calendar:
     *
     * - Local: the row itself moves ([moveException]). Nothing but the
     *   device reads it, and a move keeps every column and child row. The
     *   new master is keyed by [SeriesRowStore.ensureLocalSeriesSyncId]
     *   first (#153): the provider pairs an exception with its slot by
     *   ORIGINAL_SYNC_ID, not ORIGINAL_ID.
     * - Synced: the occurrence is copied to a fresh exception of the new
     *   master and the old row deleted ([copyException]). An uploaded
     *   exception's `_sync_id` is the server's name for "this occurrence of
     *   the OLD series", and rewriting ORIGINAL_ID/ORIGINAL_SYNC_ID locally
     *   does not rename it: once the truncated old series reaches the
     *   server, the server drops that instance as outside it and the
     *   adapter deletes the row outright, taking the user's edit with it
     *   (seen with Google's adapter on device). A fresh keyless row is new
     *   to the server, and the old row's tombstone tells it the old one is
     *   gone.
     *
     * Best-effort, like the delete path's sweep: by the time it runs the
     * new series is inserted and the old one truncated, so the split has
     * happened and the caller is told so whatever happens here. Reporting
     * a failure instead would invite a retry that splits the series again.
     * Each occurrence carries on its own: one that fails stays on the old
     * series, past its UNTIL, as it was before #158, and the rest still
     * carry. Never throws; failures go to logcat.
     *
     * A null [shift] means the new event doesn't recur: one turned into a
     * single event has no slots for an exception to stand in, and iOS
     * drops them, so they go by the delete path's sweep
     * ([SeriesRowStore.deleteDetachedOccurrencesFrom]) instead.
     */
    fun settleAfterSplit(
        master: EventRow,
        fromInstant: Long,
        newMasterId: String,
        shift: SplitShift?
    ) {
        try {
            if (shift != null) {
                carryOrThrow(master, fromInstant, newMasterId, shift)
            } else {
                store.deleteDetachedOccurrencesFrom(master, fromInstant)
            }
        } catch (e: Exception) {
            val outcome = if (shift != null) "carried to $newMasterId" else "removed"
            android.util.Log.w(
                LOG_TAG,
                "Split of event ${master.id} committed, but its detached " +
                    "occurrences past it could not be $outcome",
                e
            )
        }
    }

    /** The carry half of [settleAfterSplit], which owns its failure contract. */
    private fun carryOrThrow(
        master: EventRow,
        fromInstant: Long,
        newMasterId: String,
        shift: SplitShift
    ) {
        val exceptions = detachedOccurrencesFrom(master, fromInstant, shift)
        if (exceptions.isEmpty()) return

        val newSeries = store.readRecurringRow(newMasterId).getOrThrow()
        if (master.account.isLocal) {
            // A local series always comes back keyed: the one it had or the
            // one just assigned.
            val newKey = checkNotNull(store.ensureLocalSeriesSyncId(newSeries).getOrThrow()) {
                "Local series $newMasterId has no key"
            }
            for (exception in exceptions) {
                carryOne(exception.id, newMasterId) {
                    moveException(exception, newMasterId, newKey, shift)
                }
            }
        } else {
            for (exception in exceptions) {
                carryOne(exception.id, newMasterId) {
                    copyException(exception, newSeries, shift, master.account)
                }
            }
        }

        // The new series was expanded when it was inserted, before it had
        // any exceptions, and moving them onto it does not re-expand it: it
        // would still generate the slots they now stand in for. (After a
        // copy it is needed too: the new synced master is not keyed yet, so
        // the copy's exception insert drops its occurrences from the
        // Instances cache, as #163.) A zero row count is logged, not
        // thrown: the exceptions are already carried.
        if (store.rewriteSeriesForReexpand(newSeries.row, newSeries.rrule) == 0) {
            android.util.Log.w(
                LOG_TAG,
                "Could not re-expand series $newMasterId after carrying its exceptions (#163)"
            )
        }
    }

    /**
     * One exception row the carry takes over: its `_ID`, the slot it stands
     * in for on the new series, and its own time as stored: DTSTART, and
     * DTEND or DURATION, whichever the row keeps. The one read of the
     * occurrence's time: [moveException] and [copyException] both move it
     * from here.
     */
    private data class DetachedOccurrence(
        val id: String,
        val newSlot: Long,
        private val storedStart: Long?,
        val dtend: Long?,
        val duration: String?,
    ) {
        /**
         * The occurrence's own start. An exception row always stores one,
         * so a row without it is a broken invariant: it throws, and
         * [carryOne] skips and logs that occurrence rather than rewrite it
         * at a made-up time.
         */
        val dtstart: Long
            get() = checkNotNull(storedStart) { "Exception $id has no DTSTART" }
    }

    /**
     * Each live exception of [master] at or after [fromInstant] that
     * carries over, with the new series' slot [shift] maps its own to. A
     * deleted occurrence ([EventsService.deleteEvent]'s cancelled row) is
     * iOS's deleted date, which stays at its old time: it carries over only
     * while the split leaves its slot where it was, and a moved slot brings
     * the occurrence back. Left on the old master, past its UNTIL, it
     * cancels nothing, as before #158.
     */
    private fun detachedOccurrencesFrom(
        master: EventRow,
        fromInstant: Long,
        shift: SplitShift
    ): List<DetachedOccurrence> {
        val exceptions = mutableListOf<DetachedOccurrence>()
        // The delete path's slot rule, less the rows already tombstoned:
        // those are gone as far as the caller can tell.
        val (detached, args) = store.detachedFrom(master, fromInstant)
        resolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.ORIGINAL_INSTANCE_TIME,
                CalendarContract.Events.STATUS,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.DURATION
            ),
            "$detached AND ${CalendarContract.Events.DELETED} = 0",
            args,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events._ID)
            val slotIdx =
                cursor.getColumnIndexOrThrow(CalendarContract.Events.ORIGINAL_INSTANCE_TIME)
            val statusIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.STATUS)
            while (cursor.moveToNext()) {
                val slot = cursor.getLong(slotIdx)
                val newSlot = shift.slot(slot)
                val cancelled = !cursor.isNull(statusIdx) &&
                    cursor.getInt(statusIdx) == CalendarContract.Events.STATUS_CANCELED
                if (cancelled && newSlot != slot) continue
                exceptions += DetachedOccurrence(
                    id = cursor.getString(idIdx),
                    newSlot = newSlot,
                    storedStart = cursor.longOrNull(CalendarContract.Events.DTSTART),
                    dtend = cursor.longOrNull(CalendarContract.Events.DTEND),
                    duration = cursor.stringOrNull(CalendarContract.Events.DURATION),
                )
            }
        }
        return exceptions
    }

    /** Runs one occurrence's carry, logging and skipping it on failure. */
    private inline fun carryOne(exceptionId: String, newMasterId: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            android.util.Log.w(
                LOG_TAG,
                "Could not carry detached occurrence $exceptionId to $newMasterId",
                e
            )
        }
    }

    /**
     * Re-points [exception]'s row at its slot on [newMasterId], keyed by
     * [newKey], and moves its own start (and its DTEND, when it stores one)
     * as [shift] says: the local-calendar half of the carry.
     */
    private fun moveException(
        exception: DetachedOccurrence,
        newMasterId: String,
        newKey: String,
        shift: SplitShift
    ) {
        store.updateEventRow(
            exception.id,
            ContentValues().apply {
                put(CalendarContract.Events.ORIGINAL_ID, newMasterId.toLong())
                put(CalendarContract.Events.ORIGINAL_SYNC_ID, newKey)
                put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, exception.newSlot)
                val start = shift.start(exception.dtstart)
                if (start != exception.dtstart) {
                    put(CalendarContract.Events.DTSTART, start)
                    if (exception.dtend != null) {
                        put(
                            CalendarContract.Events.DTEND,
                            start + (exception.dtend - exception.dtstart)
                        )
                    }
                }
            }
        )
    }

    /**
     * Writes [exception]'s occurrence afresh as the exception of
     * [newSeries] at its slot there, its start moved as [shift] says, then
     * deletes the old row: the synced-calendar half of the carry.
     *
     * What the copy keeps: every occurrence-level column the plugin reads
     * or the user can set per occurrence ([carriedOccurrenceColumns], plus
     * the time as DTSTART/DURATION), and the occurrence's own Reminders and
     * Attendees rows, which replace whatever the provider seeds an
     * exception with from its master. What it drops: ExtendedProperties
     * rows, which only a sync adapter may write, and which the plugin
     * neither reads nor writes; and the adapter's own columns (`_sync_id`,
     * SYNC_DATA*, UID_2445), which are the server's name for the old row
     * and are what the copy must not carry.
     *
     * The copy is a plain insert through CONTENT_EXCEPTION_URI with no
     * `_sync_id`, so it is DIRTY and new to the server. (It skips
     * EventsService.insertException's #153 keying, which a synced series
     * never takes: its adapter owns the key. It also skips
     * insertException's #163 re-expand, which [carryOrThrow] supplies once
     * for the whole carry.) The new master is usually
     * not uploaded yet, which leaves the copy's ORIGINAL_SYNC_ID empty
     * until it is: the provider's `original_sync_update` trigger fills it
     * in when the adapter keys the master. The delete goes through
     * [SeriesRowStore.deleteUri] (plain on a synced account), so an
     * uploaded row stays as a tombstone for the adapter to send.
     *
     * The whole copy — the exception insert, its child rows and the old
     * row's delete — is one [android.content.ContentResolver.applyBatch],
     * which the Calendar Provider applies in one transaction: all of it or
     * none, so a failure leaves the old row alone rather than neither or
     * both. The delete must match exactly the one row, or the batch fails.
     * Throws on failure; the caller skips the occurrence.
     */
    private fun copyException(
        exception: DetachedOccurrence,
        newSeries: SeriesRow,
        shift: SplitShift,
        account: CalendarAccount
    ) {
        val exceptionId = exception.id
        // The end goes as DURATION, the column the provider expects on an
        // exception of a recurring parent. An exception row always carries
        // DTEND or a readable DURATION, so a row with neither has no end to
        // copy rather than one to invent.
        val dtstart = exception.dtstart
        val end = storedEndMillis(dtstart, exception.dtend, exception.duration)
            ?: throw IllegalStateException(
                "Exception $exceptionId has neither DTEND nor a readable DURATION"
            )
        // Gone since the listing: nothing left to carry.
        val values = readOccurrenceColumns(exceptionId) ?: return
        values.put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, exception.newSlot)
        values.put(CalendarContract.Events.DTSTART, shift.start(dtstart))
        values.put(CalendarContract.Events.DURATION, "P${(end - dtstart) / 1000}S")

        val oldId = exceptionId.toLong()
        val copyUri = CalendarContract.Events.CONTENT_EXCEPTION_URI
            .buildUpon()
            .appendPath(newSeries.row.id)
            .build()
        // Every child row is keyed to the copy by a back-reference to the
        // result of this first operation, the copy's insert.
        val copyOp = 0
        // The one selection argument of each child-row delete below, which
        // that back-reference fills in.
        val eventIdArg = 0
        val ops = arrayListOf(
            ContentProviderOperation.newInsert(copyUri).withValues(values).build()
        )

        ops += ContentProviderOperation.newDelete(CalendarContract.Reminders.CONTENT_URI)
            .withSelection("${CalendarContract.Reminders.EVENT_ID} = ?", arrayOf(""))
            .withSelectionBackReference(eventIdArg, copyOp)
            .build()
        for (reminder in readReminderRows(oldId)) {
            ops += ContentProviderOperation.newInsert(CalendarContract.Reminders.CONTENT_URI)
                .withValues(reminder)
                .withValueBackReference(CalendarContract.Reminders.EVENT_ID, copyOp)
                .build()
        }

        // The provider seeds an exception with its master's guest list, and
        // the occurrence's own (the one getEvent returns for it) must win.
        ops += ContentProviderOperation.newDelete(CalendarContract.Attendees.CONTENT_URI)
            .withSelection("${CalendarContract.Attendees.EVENT_ID} = ?", arrayOf(""))
            .withSelectionBackReference(eventIdArg, copyOp)
            .build()
        for (attendee in readAttendeeRows(oldId)) {
            ops += ContentProviderOperation.newInsert(CalendarContract.Attendees.CONTENT_URI)
                .withValues(attendee)
                .withValueBackReference(CalendarContract.Attendees.EVENT_ID, copyOp)
                .build()
        }

        ops += ContentProviderOperation.newDelete(store.deleteUri(account))
            .withSelection("${CalendarContract.Events._ID} = ?", arrayOf(exceptionId))
            .withExpectedCount(1)
            .build()

        resolver.applyBatch(CalendarContract.AUTHORITY, ops)
    }

    /**
     * The occurrence-level Events columns [copyException] carries as they
     * are stored, each one set (nulls included) so nothing is inherited
     * from the new master. The time goes separately, as DTSTART/DURATION.
     * Columns the provider derives (IS_ORGANIZER, SELF_ATTENDEE_STATUS,
     * which follows the copied Attendees rows) and the adapter's own are
     * left out.
     */
    private val carriedOccurrenceColumns = arrayOf(
        CalendarContract.Events.TITLE,
        CalendarContract.Events.DESCRIPTION,
        CalendarContract.Events.EVENT_LOCATION,
        CalendarContract.Events.CUSTOM_APP_URI,
        CalendarContract.Events.CUSTOM_APP_PACKAGE,
        CalendarContract.Events.ALL_DAY,
        CalendarContract.Events.EVENT_TIMEZONE,
        CalendarContract.Events.EVENT_END_TIMEZONE,
        CalendarContract.Events.AVAILABILITY,
        CalendarContract.Events.STATUS,
        CalendarContract.Events.HAS_ALARM,
        CalendarContract.Events.ACCESS_LEVEL,
        CalendarContract.Events.EVENT_COLOR,
        CalendarContract.Events.EVENT_COLOR_KEY,
        CalendarContract.Events.ORGANIZER,
        CalendarContract.Events.HAS_ATTENDEE_DATA,
        CalendarContract.Events.GUESTS_CAN_MODIFY,
        CalendarContract.Events.GUESTS_CAN_INVITE_OTHERS,
        CalendarContract.Events.GUESTS_CAN_SEE_GUESTS
    )

    /**
     * Exception row [exceptionId]'s [carriedOccurrenceColumns] as the values
     * of a fresh exception insert; null when the row is gone. The time is
     * [copyException]'s to add, from the listing.
     */
    private fun readOccurrenceColumns(exceptionId: String): ContentValues? =
        resolver.query(
            CalendarContract.Events.CONTENT_URI,
            carriedOccurrenceColumns,
            "${CalendarContract.Events._ID} = ?",
            arrayOf(exceptionId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            ContentValues().apply { cursor.copyColumnsInto(this, carriedOccurrenceColumns) }
        }

    /**
     * Event [eventId]'s [CalendarContract.Reminders] rows, whatever the
     * method, as insert values without their EVENT_ID.
     */
    private fun readReminderRows(eventId: Long): List<ContentValues> =
        readChildRows(
            CalendarContract.Reminders.CONTENT_URI,
            CalendarContract.Reminders.EVENT_ID,
            eventId,
            arrayOf(CalendarContract.Reminders.MINUTES, CalendarContract.Reminders.METHOD)
        )

    /**
     * Event [eventId]'s [CalendarContract.Attendees] rows, organizer row
     * included, as insert values without their EVENT_ID.
     */
    private fun readAttendeeRows(eventId: Long): List<ContentValues> =
        readChildRows(
            CalendarContract.Attendees.CONTENT_URI,
            CalendarContract.Attendees.EVENT_ID,
            eventId,
            arrayOf(
                CalendarContract.Attendees.ATTENDEE_NAME,
                CalendarContract.Attendees.ATTENDEE_EMAIL,
                CalendarContract.Attendees.ATTENDEE_RELATIONSHIP,
                CalendarContract.Attendees.ATTENDEE_TYPE,
                CalendarContract.Attendees.ATTENDEE_STATUS,
                CalendarContract.Attendees.ATTENDEE_IDENTITY,
                CalendarContract.Attendees.ATTENDEE_ID_NAMESPACE
            )
        )

    /**
     * The [columns] of every row of child table [uri] whose [eventIdColumn]
     * is [eventId], copied as stored (nulls included) into insert values.
     */
    private fun readChildRows(
        uri: Uri,
        eventIdColumn: String,
        eventId: Long,
        columns: Array<String>
    ): List<ContentValues> {
        val rows = mutableListOf<ContentValues>()
        resolver.query(
            uri,
            columns,
            "$eventIdColumn = ?",
            arrayOf(eventId.toString()),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                rows += ContentValues().apply { cursor.copyColumnsInto(this, columns) }
            }
        }
        return rows
    }
}
