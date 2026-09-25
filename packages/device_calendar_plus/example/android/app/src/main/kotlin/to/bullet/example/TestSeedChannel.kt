package to.bullet.example

import android.accounts.Account
import android.accounts.AccountManager
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.CalendarContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Test-only channel used by the integration tests to seed calendar
 * provider state the plugin deliberately can't write itself. The Dart side
 * is `integration_test/test_seed.dart`, which owns the channel name and a
 * typed wrapper per method.
 */
object TestSeedChannel {
    fun register(flutterEngine: FlutterEngine, context: Context) {
        val contentResolver = context.contentResolver
        val accountManager = AccountManager.get(context)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "to.bullet.device_calendar_plus_example/test"
        ).setMethodCallHandler { call, result ->
            fun eventId(): Long = call.argument<String>("eventId")!!.toLong()
            fun instanceStart(): Long = call.argument<Number>("instanceStart")!!.toLong()
            when (call.method) {
                "setEventColor" -> result.reply {
                    contentResolver.setEventColor(eventId(), call.argument<Number>("color")!!.toInt())
                }
                "deleteEventPlain" -> result.reply { contentResolver.deleteEventPlain(eventId()) }
                "insertKeylessException" -> result.reply {
                    contentResolver.insertKeylessException(
                        masterId = eventId(),
                        instanceStart = instanceStart(),
                        instanceEnd = call.argument<Number>("instanceEnd")!!.toLong(),
                        title = call.argument<String>("title")!!
                    )
                }
                "readSyncIds" -> result.reply { contentResolver.readSyncIds(eventId()) }
                "createSyncedCalendar" -> result.reply {
                    accountManager.addAccountExplicitly(SYNCED_ACCOUNT, null, null)
                    contentResolver.createSyncedCalendar(call.argument<String>("name")!!)
                }
                "removeSyncedAccount" -> result.reply {
                    accountManager.removeAccountExplicitly(SYNCED_ACCOUNT)
                }
                "markUploaded" -> result.reply {
                    contentResolver.markUploaded(eventId())
                    null // Unit is not a channel value; the check inside is the answer.
                }
                "readSyncState" -> result.reply { contentResolver.readSyncState(eventId()) }
                "exceptionIdOf" -> result.reply {
                    contentResolver.exceptionIdOf(eventId(), instanceStart())
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The account the synced test calendar lives under. Its type is the one
     * [TestAuthenticatorService] answers for — the example app's own, so the
     * app may register it — which to the provider makes it "synced"
     * (anything but ACCOUNT_TYPE_LOCAL) while no sync adapter exists for it.
     */
    private const val SYNCED_ACCOUNT_NAME = "synced@example.test"
    private const val SYNCED_ACCOUNT_TYPE = "to.bullet.device_calendar_plus_example"
    private val SYNCED_ACCOUNT = Account(SYNCED_ACCOUNT_NAME, SYNCED_ACCOUNT_TYPE)

    /**
     * EVENT_COLOR is sync-adapter-owned, so stamps [color] on [eventId] the
     * way a sync adapter would: a CALLER_IS_SYNCADAPTER update scoped to the
     * row's own account. This simulates an external app (e.g. Google
     * Calendar) assigning a custom event color. Returns the rows updated.
     */
    private fun ContentResolver.setEventColor(eventId: Long, color: Int): Int {
        val (accountName, accountType) = accountOf(eventId)
        val values = ContentValues().apply {
            put(CalendarContract.Events.EVENT_COLOR, color)
        }
        return update(eventUri(eventId).asSyncAdapter(accountName, accountType), values, null, null)
    }

    /**
     * A plain (non-sync-adapter) delete of [eventId], the kind another app
     * issues. On an event with a `_sync_id` the provider does not remove the
     * row but tombstones it (DELETED=1) for a sync adapter to collect — the
     * state the plugin's tombstone filter has to see through. Returns the
     * rows the provider reports touched.
     */
    private fun ContentResolver.deleteEventPlain(eventId: Long): Int =
        delete(eventUri(eventId), null, null)

    /**
     * The write an older plugin version made for a per-occurrence edit: a
     * plain insert on the exception URI against a master with no `_sync_id`,
     * so the exception gets no `original_sync_id` either and the provider
     * drops the master's own occurrences from its Instances cache (#153's
     * on-disk state). Lets the suite reach the upgrade re-key the plugin
     * performs before its own next exception write. Returns the exception's
     * event ID.
     */
    private fun ContentResolver.insertKeylessException(
        masterId: Long,
        instanceStart: Long,
        instanceEnd: Long,
        title: String
    ): String? {
        val uri = ContentUris.withAppendedId(
            CalendarContract.Events.CONTENT_EXCEPTION_URI,
            masterId
        )
        // The provider refuses DTEND on an exception ("Exceptions can't
        // overwrite dtend"); it takes DURATION, as the plugin's own writer
        // sends.
        val values = ContentValues().apply {
            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, instanceStart)
            put(CalendarContract.Events.DTSTART, instanceStart)
            put(CalendarContract.Events.DURATION, "P${(instanceEnd - instanceStart) / 1000}S")
            put(CalendarContract.Events.TITLE, title)
        }
        return insert(uri, values)?.lastPathSegment
    }

    /**
     * The provider's own keys for an event row: `_sync_id` and
     * `original_sync_id`, as {"syncId": ..., "originalSyncId": ...} (null
     * for an unkeyed row, or the whole map null when the row is missing).
     * The plugin never exposes them, but they are what the provider's full
     * regeneration (a timezone change, a reboot) keys a series' exceptions
     * by, so a test of the #153 re-key has to read them directly.
     */
    private fun ContentResolver.readSyncIds(eventId: Long): Map<String, String?>? =
        queryOne(
            eventUri(eventId),
            arrayOf(CalendarContract.Events._SYNC_ID, CalendarContract.Events.ORIGINAL_SYNC_ID)
        ) { cursor ->
            mapOf(
                "syncId" to cursor.getString(0),
                "originalSyncId" to cursor.getString(1)
            )
        }

    /**
     * A calendar a sync adapter owns — any account type but
     * ACCOUNT_TYPE_LOCAL — inserted the way that adapter would, under
     * [SYNCED_ACCOUNT]: an account of the example app's own type that no
     * adapter answers to. The emulator has no synced account, and a real
     * device's Google account must not receive test rows, so the tests stand
     * one up: the provider's sync-adapter branches (#132) turn on the account
     * type alone. The caller registers the account first (idempotently),
     * since the provider drops the calendars of any account the
     * AccountManager does not know on every cold start. Returns the
     * calendar's ID.
     */
    private fun ContentResolver.createSyncedCalendar(name: String): String? {
        val uri = CalendarContract.Calendars.CONTENT_URI
            .asSyncAdapter(SYNCED_ACCOUNT_NAME, SYNCED_ACCOUNT_TYPE)
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, SYNCED_ACCOUNT_NAME)
            put(CalendarContract.Calendars.ACCOUNT_TYPE, SYNCED_ACCOUNT_TYPE)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, SYNCED_ACCOUNT_NAME)
            put(CalendarContract.Calendars.NAME, name)
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
            put(
                CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
                CalendarContract.Calendars.CAL_ACCESS_OWNER
            )
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF00FF)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.VISIBLE, 1)
        }
        return insert(uri, values)?.lastPathSegment
    }

    /**
     * Puts [eventId] in the state a sync adapter leaves an event in once the
     * server has it — a `_sync_id`, DIRTY cleared — written as the adapter
     * for the row's own account. From here a plain write is what the adapter
     * uploads next (DIRTY=1 on an edit, a DELETED=1 tombstone on a delete),
     * and a sync-adapter write is one the server never hears of (#132).
     * Fails when the row is missing, so no test has to check a count.
     */
    private fun ContentResolver.markUploaded(eventId: Long) {
        val (accountName, accountType) = accountOf(eventId)
        val values = ContentValues().apply {
            put(CalendarContract.Events._SYNC_ID, "seed:${java.util.UUID.randomUUID()}")
            put(CalendarContract.Events.DIRTY, 0)
        }
        val updated =
            update(eventUri(eventId).asSyncAdapter(accountName, accountType), values, null, null)
        check(updated == 1) { "Expected to mark one event row uploaded, updated $updated" }
    }

    /**
     * What a sync adapter would find to upload for an event row: its DELETED
     * and DIRTY flags, as {"deleted": ..., "dirty": ...}, or null when the
     * row is gone altogether. Read off the Events table, which — unlike
     * Instances and the plugin's own reads — still lists a DELETED=1
     * tombstone.
     */
    private fun ContentResolver.readSyncState(eventId: Long): Map<String, Boolean>? =
        queryOne(
            eventUri(eventId),
            arrayOf(CalendarContract.Events.DELETED, CalendarContract.Events.DIRTY)
        ) { cursor ->
            mapOf(
                "deleted" to (cursor.getInt(0) == 1),
                "dirty" to (cursor.getInt(1) == 1)
            )
        }

    /**
     * The event ID of the exception row written against master [masterId]
     * for the occurrence at [instanceStart], or null when there is none. The
     * plugin returns no ID for a cancelled occurrence, so its row is found by
     * the slot it replaced.
     */
    private fun ContentResolver.exceptionIdOf(masterId: Long, instanceStart: Long): String? =
        queryOne(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events._ID),
            "${CalendarContract.Events.ORIGINAL_ID} = ? AND " +
                "${CalendarContract.Events.ORIGINAL_INSTANCE_TIME} = ?",
            arrayOf(masterId.toString(), instanceStart.toString())
        ) { cursor -> cursor.getLong(0).toString() }

    /** The (ACCOUNT_NAME, ACCOUNT_TYPE) of [eventId]'s calendar, off the Events view. */
    private fun ContentResolver.accountOf(eventId: Long): Pair<String, String> =
        queryOne(
            eventUri(eventId),
            arrayOf(CalendarContract.Events.ACCOUNT_NAME, CalendarContract.Events.ACCOUNT_TYPE)
        ) { cursor -> Pair(cursor.getString(0), cursor.getString(1)) }
            ?: throw IllegalStateException("No event row with ID $eventId")

    /** [map] of the first row [uri] yields for [selection], or null when there is none. */
    private fun <T> ContentResolver.queryOne(
        uri: Uri,
        projection: Array<String>,
        selection: String? = null,
        selectionArgs: Array<String>? = null,
        map: (Cursor) -> T
    ): T? =
        query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            map(cursor)
        }

    /** The Events row URI of [eventId]. */
    private fun eventUri(eventId: Long): Uri =
        ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)

    /**
     * This URI with sync-adapter context for the account: the write goes as
     * that account's adapter, which may set the sync-owned columns and whose
     * changes the provider takes as the server's own (never marked for
     * upload).
     */
    private fun Uri.asSyncAdapter(accountName: String, accountType: String): Uri =
        buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
            .build()

    /**
     * Answers with [block]'s value, or a `TEST_SEED_FAILED` error carrying
     * the exception's message: the one envelope every seed method shares.
     */
    private inline fun MethodChannel.Result.reply(block: () -> Any?) {
        try {
            success(block())
        } catch (e: Exception) {
            error("TEST_SEED_FAILED", e.message, null)
        }
    }
}
