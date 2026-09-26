package to.bullet.device_calendar_plus_android


// The duration arithmetic behind EventsService: how a row's end is derived
// from DTEND or DTSTART + DURATION. Pure functions with no Context, provider
// or android.* access, so a plain JVM unit test can drive them directly. The
// all-day date conversions live in AllDayDates.

/**
 * [millis] floored to a whole second. Event times are written at second
 * precision, as iOS EventKit stores them: the provider keeps whatever millis
 * DTSTART is given, but some versions (API 30, Samsung) expand a series'
 * occurrences at whole seconds, so a sub-second master would disagree with
 * its own occurrences (#165).
 */
internal fun wholeSeconds(millis: Long): Long = Math.floorDiv(millis, 1000L) * 1000L

/**
 * The DTSTART/DTEND value written for a caller's [millis]: UTC midnight of
 * its local date for an all-day event (the provider reads an all-day time as
 * a UTC date), else the instant at [wholeSeconds] (#165).
 */
internal fun storageMillis(millis: Long, isAllDay: Boolean): Long =
    if (isAllDay) AllDayDates.localDateToUtcMidnight(millis) else wholeSeconds(millis)

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
