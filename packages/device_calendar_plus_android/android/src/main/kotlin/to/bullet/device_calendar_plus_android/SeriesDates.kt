package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

/**
 * The time zone that frames a series' calendar days: the event's own
 * (device default when [timeZoneId] is null), except that all-day events
 * are stored as UTC midnight and so live in UTC.
 */
internal fun seriesTimeZone(timeZoneId: String?, isAllDay: Boolean): TimeZone =
    when {
        isAllDay -> TimeZone.getTimeZone("UTC")
        timeZoneId != null -> TimeZone.getTimeZone(timeZoneId)
        else -> TimeZone.getDefault()
    }

/**
 * Whole calendar days from [fromMillis] to [toMillis] in [tz]. Rounds the
 * start-of-day difference so a DST transition (a 23- or 25-hour day) still
 * yields an integer day count.
 */
internal fun calendarDaysBetween(fromMillis: Long, toMillis: Long, tz: TimeZone): Int {
    val diff = AllDayDates.localMidnight(toMillis, tz) - AllDayDates.localMidnight(fromMillis, tz)
    return Math.round(diff.toDouble() / AllDayDates.MILLIS_PER_DAY).toInt()
}

/**
 * A series' anchor moved from one instant to another, as a rule for moving
 * the rest of the series with it: by the whole calendar days the anchor
 * moved, counted in the series' time zone [tz] (see [seriesTimeZone]). Not
 * by the raw millisecond shift, which a DST change between the anchor and
 * a later date would put an hour off. The anchor-shift that lets
 * [EventsService.updateRecurring] move both the time and the day of a
 * series (#103), and where a `thisAndFollowing` split carries what it
 * carries (#158); iOS's counterparts are `SeriesDates.shiftStart` and EKSpan.futureEvents.
 *
 * [slot] is where a date lands on the moved series: that many days on, at
 * the new anchor's wall-clock time of day (midnight for all-day, which is
 * stored as UTC midnight). [start] is where a detached occurrence's own
 * start goes: that many days on, at its own time of day.
 */
internal class SplitShift private constructor(
    private val dayDelta: Int,
    private val tz: TimeZone,
    private val hour: Int,
    private val minute: Int,
    private val second: Int,
    private val millisecond: Int,
) {

    /** [old] moved by the anchor's days, at the new anchor's time of day. */
    fun slot(old: Long): Long {
        val cal = addDays(old)
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, second)
        cal.set(Calendar.MILLISECOND, millisecond)
        return cal.timeInMillis
    }

    /** [old] moved by the anchor's days, keeping its own time of day. */
    fun start(old: Long): Long = addDays(old).timeInMillis

    private fun addDays(millis: Long): Calendar =
        Calendar.getInstance(tz).apply {
            timeInMillis = millis
            add(Calendar.DAY_OF_YEAR, dayDelta)
        }

    companion object {
        /**
         * The shift that moves the anchor [fromAnchor] to [toAnchor], in
         * the series' time zone [tz]. All-day series shift by whole days
         * with the time of day left at midnight; timed ones carry the full
         * wall-clock time of day (down to millis) from [toAnchor], matching
         * iOS's shiftStart so the platforms agree. Callers pass whole-second
         * anchors (floored at the plugin seam or by [resolveSeriesTimes],
         * #165), so the millisecond carried is 0 in practice; it is still
         * set so [slot] clears the millis of the start it moves.
         */
        fun of(fromAnchor: Long, toAnchor: Long, tz: TimeZone, isAllDay: Boolean): SplitShift {
            val target = Calendar.getInstance(tz).apply { timeInMillis = toAnchor }
            return SplitShift(
                dayDelta = calendarDaysBetween(fromAnchor, toAnchor, tz),
                tz = tz,
                hour = if (isAllDay) 0 else target.get(Calendar.HOUR_OF_DAY),
                minute = if (isAllDay) 0 else target.get(Calendar.MINUTE),
                second = if (isAllDay) 0 else target.get(Calendar.SECOND),
                millisecond = if (isAllDay) 0 else target.get(Calendar.MILLISECOND),
            )
        }
    }
}

/**
 * Resolves the start and duration for a series-level edit; iOS's
 * counterpart is `resolveSeriesStart`.
 *
 * When [targetStart] is given the start is shifted by the wall-clock
 * delta from [referenceMillis] to [targetStart] (see [SplitShift]).
 * [targetStart] is already in the frame after the edit
 * ([resolveTargetStart]), while [baseMillis] and [referenceMillis] are in
 * the row's stored frame. Unlike the day-move check, which reads each in its
 * own zone, this reads all three in the one post-edit zone. That differs
 * from the stored zone only when the same edit toggles all-day, and it is
 * still safe then: base and reference are the same instant or occurrences
 * of the same series at the same wall-clock time, so the wrong zone moves
 * both onto the same wrong day (unless a DST change between them carries
 * just one across the other zone's midnight), the error cancels out of the
 * day delta, and
 * [SplitShift.slot] then resets the time of day for the new frame. Keep
 * that invariant, or pass the stored zone in, when changing either input.
 * A new [rrule] then moves it onto the first day the rule generates, keeping
 * its wall-clock time — the anchor a series switched to a new rule must
 * have, or the provider emits the old day as an extra occurrence (#140).
 * A rule that generates nothing within five years of the anchor fails
 * with INVALID_ARGUMENTS rather than leaving that orphan behind. The
 * duration is overridden when [durationMinutes] is given.
 */
internal fun resolveSeriesTimes(
    baseMillis: Long,
    referenceMillis: Long,
    existingDurationMillis: Long,
    targetStart: Long?,
    durationMinutes: Int?,
    rrule: String?,
    timeZoneId: String?,
    isAllDay: Boolean
): Result<Pair<Long, Long>> {
    val tz = seriesTimeZone(timeZoneId, isAllDay)
    // A slot copies the new start's time of day, already whole seconds.
    // With no new start the stored start is kept as is, even with millis
    // from an older version or another app: rewriting it would orphan
    // detached occurrences keyed at those millis (#165).
    val shiftedStart = if (targetStart != null) {
        SplitShift.of(referenceMillis, targetStart, tz, isAllDay).slot(baseMillis)
    } else {
        baseMillis
    }
    val newStart = if (rrule != null) {
        // A rule re-anchor moves the series anyway, so it drops any stored
        // millis too, like every event time the plugin writes (#165).
        RecurrenceAnchor.firstMatch(rrule, shiftedStart, tz)?.let(::wholeSeconds)
            ?: return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.INVALID_ARGUMENTS,
                    "recurrenceRule generates no occurrences within five years of the anchor"
                )
            )
    } else {
        shiftedStart
    }
    val newDurationMs = if (durationMinutes != null) {
        durationMinutes.toLong() * 60_000L
    } else {
        // Always floored, so the written duration is whole seconds (the
        // recurring path writes DURATION in seconds anyway). The end written
        // from it is whole only when the start is: a millis start nothing
        // moves is kept, so its end keeps those millis too (#165).
        wholeSeconds(existingDurationMillis)
    }
    return Result.success(Pair(newStart, newDurationMs))
}

/**
 * Whether moving the anchor from [referenceMillis] to [targetMillis] would
 * change the day-spec that [rrule] pins explicitly: the weekday for a
 * BYDAY rule, the day-of-month for a BYMONTHDAY rule, or the month for a
 * BYMONTH rule. When it would, an anchor shift alone can't say what the new
 * pattern should be (see updateRecurring docs), so the caller must supply a
 * new rule. Rules with no explicit anchor return false — they follow the
 * anchor freely. iOS's counterpart is `SeriesDates.dayMoveConflictsWithRule`.
 *
 * Each instant is read in the zone that frames its own calendar day (see
 * [seriesTimeZone]): an all-day one is stored as UTC midnight, so it is read
 * in UTC. Reading a UTC-midnight date in the device zone puts it on the day
 * before west of UTC (#144).
 */
internal fun dayMoveConflictsWithRule(
    rrule: String,
    referenceMillis: Long,
    referenceZone: TimeZone,
    targetMillis: Long,
    targetZone: TimeZone
): Boolean {
    val parts = RruleString.params(rrule)
    val hasByDay = "BYDAY" in parts
    val hasByMonthDay = "BYMONTHDAY" in parts
    val hasByMonth = "BYMONTH" in parts
    if (!hasByDay && !hasByMonthDay && !hasByMonth) return false
    val ref = Calendar.getInstance(referenceZone).apply { timeInMillis = referenceMillis }
    val tgt = Calendar.getInstance(targetZone).apply { timeInMillis = targetMillis }
    fun changed(field: Int) = ref.get(field) != tgt.get(field)
    if (hasByDay && changed(Calendar.DAY_OF_WEEK)) return true
    if (hasByMonthDay && changed(Calendar.DAY_OF_MONTH)) return true
    if (hasByMonth && changed(Calendar.MONTH)) return true
    return false
}

/**
 * The caller's new series start brought into the stored frame, or the
 * INVALID_ARGUMENTS failure when it moves the day of a series whose rule pins
 * that day explicitly (see [dayMoveConflictsWithRule]) and no new rule is
 * given. Null when there is no new start. Runs before any write.
 *
 * [newStartMillis] is a local instant (a Dart DateTime) meant in
 * [deviceZone]; an all-day series is stored as UTC midnight, so it becomes
 * that via [storageMillis], as updateEvent does. The check and the anchor
 * shift then compare like with like on either side of UTC (#144). The stored
 * [referenceMillis] is read in the row's own frame ([rowAllDay],
 * [rowTimeZone]); the target in the frame after the edit
 * ([effectiveIsAllDay]), which differs when the same edit toggles all-day.
 * Implicit rules (no BYDAY/BYMONTHDAY/BYMONTH) just follow the anchor.
 */
internal fun resolveTargetStart(
    newStartMillis: Long?,
    rowRrule: String?,
    rowAllDay: Boolean,
    rowTimeZone: String?,
    referenceMillis: Long,
    effectiveIsAllDay: Boolean,
    changingRule: Boolean,
    deviceZone: TimeZone = TimeZone.getDefault()
): Result<Long?> {
    if (newStartMillis == null) return Result.success(null)
    val targetStart = storageMillis(newStartMillis, effectiveIsAllDay, deviceZone)
    if (!changingRule && rowRrule != null &&
        dayMoveConflictsWithRule(
            rowRrule,
            referenceMillis,
            seriesTimeZone(rowTimeZone, rowAllDay),
            targetStart,
            seriesTimeZone(rowTimeZone, effectiveIsAllDay)
        )
    ) {
        return Result.failure(
            CalendarException(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "start moves this series to a different day, but its " +
                    "recurrence rule pins specific days. Pass a " +
                    "recurrenceRule to specify the new pattern."
            )
        )
    }
    return Result.success(targetStart)
}
