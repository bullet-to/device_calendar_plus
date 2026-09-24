package to.bullet.device_calendar_plus_android

import android.net.Uri
import android.provider.CalendarContract
import java.util.Calendar
import java.util.TimeZone

// The time and duration arithmetic behind EventsService: how the Calendar
// Provider stores an all-day day, how a row's end is derived, and how an
// Instances window is addressed. Pure functions with no Context or provider
// access, so a unit test can drive them directly.

/**
 * Converts local-time millis to UTC midnight, preserving the calendar date.
 * Used when writing all-day events: Android stores them as UTC midnight
 * boundaries, so a local "June 5" must become "June 5 00:00 UTC".
 */
internal fun localDateToUtcMidnight(localMillis: Long): Long {
    val local = Calendar.getInstance()
    local.timeInMillis = localMillis
    val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
    utc.set(
        local.get(Calendar.YEAR),
        local.get(Calendar.MONTH),
        local.get(Calendar.DAY_OF_MONTH),
        0, 0, 0
    )
    utc.set(Calendar.MILLISECOND, 0)
    return utc.timeInMillis
}

/**
 * Converts UTC millis to local midnight, preserving the calendar date.
 * Used when reading all-day events: Android stores them as UTC midnight
 * boundaries, and we need to present the date in the device's local time.
 */
internal fun utcToLocalMidnight(utcMillis: Long): Long {
    val utcCal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
    utcCal.timeInMillis = utcMillis
    val localCal = Calendar.getInstance()
    localCal.set(
        utcCal.get(Calendar.YEAR),
        utcCal.get(Calendar.MONTH),
        utcCal.get(Calendar.DAY_OF_MONTH),
        0, 0, 0
    )
    localCal.set(Calendar.MILLISECOND, 0)
    return localCal.timeInMillis
}

/**
 * The Instances URI for the window [[beginMillis], [endMillis]]. The
 * Instances table can only be queried through a window, and the provider
 * matches any occurrence overlapping it.
 */
internal fun instancesUri(beginMillis: Long, endMillis: Long): Uri =
    CalendarContract.Instances.CONTENT_URI.buildUpon()
        .appendPath(beginMillis.toString())
        .appendPath(endMillis.toString())
        .build()

/** DTEND, else DTSTART + DURATION when it parses; null when neither is usable. */
internal fun storedEndMillis(dtstart: Long, dtend: Long?, duration: String?): Long? =
    dtend ?: duration?.let(::parseDurationMillis)?.let { dtstart + it }

/** Parses an RFC 5545 / Android duration string (e.g. "P3600S", "PT1H"). */
internal fun parseDurationMillis(duration: String): Long? {
    val trimmed = duration.trim()
    Regex("P(\\d+)S").matchEntire(trimmed)?.let {
        return it.groupValues[1].toLong() * 1000L
    }
    val match = Regex(
        "P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?"
    ).matchEntire(trimmed) ?: return null
    var seconds = 0L
    match.groupValues[1].toLongOrNull()?.let { seconds += it * 7 * 24 * 3600 }
    match.groupValues[2].toLongOrNull()?.let { seconds += it * 24 * 3600 }
    match.groupValues[3].toLongOrNull()?.let { seconds += it * 3600 }
    match.groupValues[4].toLongOrNull()?.let { seconds += it * 60 }
    match.groupValues[5].toLongOrNull()?.let { seconds += it }
    return seconds * 1000L
}
