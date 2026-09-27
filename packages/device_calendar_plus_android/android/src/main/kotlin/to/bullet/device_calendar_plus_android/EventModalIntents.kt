package to.bullet.device_calendar_plus_android

import android.app.Activity
import android.content.Intent
import android.provider.CalendarContract

/**
 * Launches the system calendar app's modals (#123). The plugin claims the
 * modal slot and does any provider lookup first
 * ([EventsService.findEventForModal]); this only builds the intent and starts
 * it for a result, so the data service stays free of Activity code — as on
 * iOS, where the plugin builds the EventKitUI controllers.
 */
internal object EventModalIntents {
    /**
     * Shows a calendar event using the system calendar app.
     *
     * Fires [Intent.ACTION_VIEW] (details, with an edit button) or, when [edit]
     * is true, [Intent.ACTION_EDIT].
     *
     * Caveat: `ACTION_EDIT` is honored inconsistently by calendar apps. The
     * AOSP/stock calendar opens the existing event in its editor, but **Google
     * Calendar ignores the event URI and opens a blank new-event editor** — and
     * there is no intent that reliably launches it straight into edit mode on an
     * existing event. `ACTION_VIEW` (the [edit] == false path) binds to the
     * event everywhere, so a dependable edit flow is view-then-tap-edit.
     *
     * [rowId] comes from [EventsService.findEventForModal], which runs first
     * so a missing event fails NOT_FOUND, as on iOS.
     */
    fun showEvent(activityContext: Activity, rowId: Long, timestamp: Long?, edit: Boolean, requestCode: Int): Result<Unit> {
        return try {
            val intent = Intent(if (edit) Intent.ACTION_EDIT else Intent.ACTION_VIEW)

            // Build event URI
            val eventUri = android.content.ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI,
                rowId
            )
            intent.data = eventUri
            
            // Add begin time for specific recurring event instances
            if (timestamp != null) {
                intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, timestamp)
            }
            
            // Use startActivityForResult to get a callback when the activity closes
            activityContext.startActivityForResult(intent, requestCode)
            Result.success(Unit)
        } catch (e: android.content.ActivityNotFoundException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.CALENDAR_UNAVAILABLE,
                    "Calendar app not found"
                )
            )
        } catch (e: SecurityException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to open event: ${e.message}"
                )
            )
        }
    }
    
    /**
     * Opens native calendar editor in create mode with optional pre-fill.
     */
    fun showCreateEvent(
        activityContext: Activity,
        title: String?,
        startDate: Long?,
        endDate: Long?,
        description: String?,
        location: String?,
        isAllDay: Boolean?,
        recurrenceRule: String?,
        availability: String?,
        requestCode: Int,
    ): Result<Unit> {
        return try {
            // No permission gate: ACTION_INSERT hands the event to the calendar
            // app, which saves it with its own access — the docs are explicit
            // that the caller needs neither READ_ nor WRITE_CALENDAR.
            val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)

            if (title != null) intent.putExtra(CalendarContract.Events.TITLE, title)
            if (description != null) intent.putExtra(CalendarContract.Events.DESCRIPTION, description)
            if (location != null) intent.putExtra(CalendarContract.Events.EVENT_LOCATION, location)
            if (startDate != null) intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startDate)
            if (endDate != null) intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endDate)
            // EXTRA_EVENT_ALL_DAY is a *boolean* extra — calendar apps read it
            // with getBooleanExtra, which ignores an Integer value entirely.
            if (isAllDay != null) intent.putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, isAllDay)
            if (recurrenceRule != null) intent.putExtra(CalendarContract.Events.RRULE, recurrenceRule)
            if (availability != null) {
                val availabilityValue = when (availability) {
                    "free" -> CalendarContract.Events.AVAILABILITY_FREE
                    "tentative" -> CalendarContract.Events.AVAILABILITY_TENTATIVE
                    else -> CalendarContract.Events.AVAILABILITY_BUSY
                }
                intent.putExtra(CalendarContract.Events.AVAILABILITY, availabilityValue)
            }

            activityContext.startActivityForResult(intent, requestCode)
            Result.success(Unit)
        } catch (e: android.content.ActivityNotFoundException) {
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.CALENDAR_UNAVAILABLE,
                    "Calendar app not found"
                )
            )
        } catch (e: Exception) {
            // No SecurityException special-case: ACTION_INSERT needs no calendar
            // permission, so one here isn't a calendar-permission problem and
            // mapping it to PERMISSION_DENIED would send callers down a
            // requestPermissions loop that can't help.
            Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to open create event modal: ${e.message}"
                )
            )
        }
    }
}
