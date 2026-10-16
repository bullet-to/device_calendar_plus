package to.bullet.device_calendar_plus_android

import java.util.TimeZone

// How event times are stored and derived: second precision, the all-day
// UTC-midnight dispatch (the conversions themselves live in AllDayDates), and
// a row's end from DTEND or DTSTART + DURATION. Pure functions with no
// Context, provider or android.* access, so a plain JVM unit test can drive
// them directly.

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
 * a UTC date), else the instant itself. Times arrive already at
 * [wholeSeconds]: a caller's are floored at the plugin argument seam
 * (`writtenInstant`), and [resolveSeriesTimes] floors a re-anchored stored
 * start and the stored duration. A stored start nothing moves keeps its
 * millis (#165). [zone] is the device zone [millis] was meant in; tests
 * pass it, production uses the default.
 */
internal fun storageMillis(
    millis: Long,
    isAllDay: Boolean,
    zone: TimeZone = TimeZone.getDefault()
): Long =
    if (isAllDay) AllDayDates.localDateToUtcMidnight(millis, zone) else millis

/**
 * The DTSTART and DTEND an `updateEvent` edit writes for an event starting at
 * [currentStart] (the row's DTSTART, or an occurrence's own start) and
 * lasting [durationMillis], given the caller's optional
 * [startMillis]/[endMillis], the patch's [newAllDay] and the row's
 * [rowAllDay]. Null means "leave that bound as it is".
 *
 * Each provided bound is stored in the effective frame ([storageMillis]).
 * An edit that toggles the all-day flag moves a bound it leaves out into the
 * new frame too, the way EventKit reads the dates it holds under the new
 * flag:
 * - to all-day, from [AllDayDates.toggleSpan] of the row: UTC midnight of
 *   its first local date, and the exclusive end of its last. Left timed under
 *   ALL_DAY=1, the provider read the bound as a UTC date, a day off where
 *   that isn't the local one (#203, #204).
 * - to timed, from [AllDayDates.timedSpan] of the row: local midnight of its
 *   first date, and the last second of its last. Left as UTC midnights under
 *   ALL_DAY=0, the bounds read back as the evening before west of UTC (#205,
 *   #216).
 * Without a toggle a missing bound stays null.
 */
internal fun resolveEditedBounds(
    currentStart: Long,
    durationMillis: Long,
    startMillis: Long?,
    endMillis: Long?,
    newAllDay: Boolean?,
    rowAllDay: Boolean,
    zone: TimeZone = TimeZone.getDefault()
): Pair<Long?, Long?> {
    val isAllDay = newAllDay ?: rowAllDay
    val start = startMillis?.let { storageMillis(it, isAllDay, zone) }
    val end = endMillis?.let { storageMillis(it, isAllDay, zone) }
    if (isAllDay == rowAllDay) return start to end
    val (rowStart, rowEnd) = if (isAllDay) {
        AllDayDates.toggleSpan(currentStart, durationMillis, zone)
    } else {
        AllDayDates.timedSpan(currentStart, durationMillis, zone)
    }
    return (start ?: rowStart) to (end ?: rowEnd)
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
