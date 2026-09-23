package to.bullet.example

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.provider.CalendarContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Test-only channel used by the integration tests to seed calendar
 * provider state the plugin deliberately can't write itself.
 */
object TestSeedChannel {
    fun register(flutterEngine: FlutterEngine, contentResolver: ContentResolver) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "to.bullet.device_calendar_plus_example/test"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // EVENT_COLOR is sync-adapter-owned, so stamp it the way a
                // sync adapter would: a CALLER_IS_SYNCADAPTER update scoped to
                // the plugin's local test account. This simulates an external
                // app (e.g. Google Calendar) assigning a custom event color.
                "setEventColor" -> {
                    try {
                        val eventId = call.argument<String>("eventId")!!.toLong()
                        val color = call.argument<Number>("color")!!.toInt()
                        val uri = ContentUris
                            .withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)
                            .buildUpon()
                            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                            // Plugin-created local calendars use account name
                            // "local" with ACCOUNT_TYPE_LOCAL (see the plugin's
                            // CalendarService.createCalendar).
                            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, "local")
                            .appendQueryParameter(
                                CalendarContract.Calendars.ACCOUNT_TYPE,
                                CalendarContract.ACCOUNT_TYPE_LOCAL
                            )
                            .build()
                        val values = ContentValues().apply {
                            put(CalendarContract.Events.EVENT_COLOR, color)
                        }
                        val updated = contentResolver.update(uri, values, null, null)
                        result.success(updated)
                    } catch (e: Exception) {
                        result.error("TEST_SEED_FAILED", e.message, null)
                    }
                }
                // A plain (non-sync-adapter) delete, the kind another app
                // issues. On an event with a `_sync_id` the provider does not
                // remove the row but tombstones it (DELETED=1) for a sync
                // adapter to collect — the state the plugin's tombstone
                // filter has to see through. Returns the rows the provider
                // reports touched.
                "deleteEventPlain" -> {
                    try {
                        val eventId = call.argument<String>("eventId")!!.toLong()
                        val deleted = contentResolver.delete(
                            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
                            null,
                            null
                        )
                        result.success(deleted)
                    } catch (e: Exception) {
                        result.error("TEST_SEED_FAILED", e.message, null)
                    }
                }
                // The write an older plugin version made for a per-occurrence
                // edit: a plain insert on the exception URI against a master
                // with no `_sync_id`, so the exception gets no
                // `original_sync_id` either and the provider drops the
                // master's own occurrences from its Instances cache (#153's
                // on-disk state). Lets the suite reach the upgrade re-key the
                // plugin performs before its own next exception write.
                // Returns the exception's event ID.
                "insertKeylessException" -> {
                    try {
                        val masterId = call.argument<String>("eventId")!!.toLong()
                        val instanceStart = call.argument<Number>("instanceStart")!!.toLong()
                        val instanceEnd = call.argument<Number>("instanceEnd")!!.toLong()
                        val title = call.argument<String>("title")!!
                        val uri = ContentUris.withAppendedId(
                            CalendarContract.Events.CONTENT_EXCEPTION_URI,
                            masterId
                        )
                        // The provider refuses DTEND on an exception
                        // ("Exceptions can't overwrite dtend"); it takes
                        // DURATION, as the plugin's own writer sends.
                        val values = ContentValues().apply {
                            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, instanceStart)
                            put(CalendarContract.Events.DTSTART, instanceStart)
                            put(
                                CalendarContract.Events.DURATION,
                                "P${(instanceEnd - instanceStart) / 1000}S"
                            )
                            put(CalendarContract.Events.TITLE, title)
                        }
                        val inserted = contentResolver.insert(uri, values)
                        result.success(inserted?.lastPathSegment)
                    } catch (e: Exception) {
                        result.error("TEST_SEED_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
