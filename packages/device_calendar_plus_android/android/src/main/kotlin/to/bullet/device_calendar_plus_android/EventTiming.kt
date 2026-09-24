package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

// The time and duration arithmetic behind EventsService: how the Calendar
// Provider stores an all-day day and how a row's end is derived. Pure
// functions with no Context, provider or android.* access, so a plain JVM
// unit test can drive them directly.

/**
 * Converts local-time millis to UTC midnight, preserving the calendar date.
 * E.g. Dec 25 00:00 AEDT (UTC+11) -> Dec 25 00:00 UTC. Android stores
 * all-day events as UTC midnight boundaries, so a local "June 5" must become
 * "June 5 00:00 UTC" when writing one, and a local query window must be
 * widened to the UTC midnights of its dates to read one back.
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

/** DTEND, else DTSTART + DURATION when it parses; null when neither is usable. */
internal fun storedEndMillis(dtstart: Long, dtend: Long?, duration: String?): Long? =
    dtend ?: duration?.let(::parseDurationMillis)?.let { dtstart + it }

/** Parses an RFC 5545 / Android duration string (e.g. "P3600S", "PT1H"). */
private fun parseDurationMillis(duration: String): Long? {
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
