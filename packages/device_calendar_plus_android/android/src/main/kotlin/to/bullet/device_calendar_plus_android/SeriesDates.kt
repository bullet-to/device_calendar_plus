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
 * carries (#158); iOS's counterparts are `SeriesDates.shiftStart` and
 * EKSpan.futureEvents.
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
 * What a series edit does to its recurrence rule: keep the one it has
 * ([Keep.rule] is null when the event doesn't recur), replace it, or clear
 * it. Built once from the method-channel `recurrenceRule` and
 * `clearedFields`, which the Dart `Patch` keeps mutually exclusive. iOS's
 * counterpart is `SeriesRuleEdit` in `SeriesDates.swift`.
 */
internal sealed class SeriesRuleEdit {
    data class Keep(val rule: String?) : SeriesRuleEdit()
    data class Replace(val rule: String) : SeriesRuleEdit()
    object Clear : SeriesRuleEdit()

    companion object {
        /** The edit [recurrenceRule] (or a [cleared] rule) makes to a series whose rule is [existing]. */
        fun of(recurrenceRule: String?, cleared: Boolean, existing: String?): SeriesRuleEdit =
            when {
                cleared -> Clear
                recurrenceRule != null -> Replace(recurrenceRule)
                else -> Keep(existing)
            }
    }
}

/**
 * Resolves the start and duration for a series-level edit; iOS's
 * counterparts are `resolveSeriesStart` and `resolveSeriesEnd`.
 *
 * When [targetStart] is given the start is shifted by the wall-clock
 * delta from [referenceMillis] to [targetStart] (see [SplitShift]).
 * [targetStart] is already in the frame after the edit
 * ([resolveTargetStart]), while [baseMillis] and [referenceMillis] are in
 * the row's stored frame [storedZone], yet the shift reads all three in the
 * one post-edit zone, `seriesTimeZone(timeZoneId, isAllDay)` ([isAllDay] is
 * the series' all-day state after the edit). That zone differs from
 * [storedZone] only when the same edit toggles all-day, and it is still
 * safe then: base and reference are the same instant or occurrences of the
 * same series at the same wall-clock time, so the wrong zone moves both
 * onto the same wrong day (unless a DST change between them carries just
 * one across the other zone's midnight), the error cancels out of the day
 * delta, and [SplitShift.slot] then resets the time of day for the new
 * frame. Keep that invariant, or read them in [storedZone], when changing
 * either input.
 *
 * The new start must be a day the series' rule generates, or the provider
 * emits it as an extra first occurrence (#140, #189). [ruleEdit] decides
 * how: a kept rule must generate the days a move lands on ([leavesRule]),
 * or the move fails with INVALID_ARGUMENTS; a replacing rule moves the
 * shifted start onto the first day it generates, keeping its wall-clock
 * time, and fails with INVALID_ARGUMENTS when it generates nothing within
 * five years; a cleared rule needs neither. A time-only move leaves a start
 * the kept rule doesn't generate (one anchored off its rule by another app,
 * or in another zone) where it is. A [splitsSeries] (thisAndFollowing) move
 * onto another day is also refused while the kept rule pins days (#194).
 * The duration is overridden when
 * [durationMinutes] is given.
 */
internal fun resolveSeriesTimes(
    baseMillis: Long,
    referenceMillis: Long,
    existingDurationMillis: Long,
    targetStart: Long?,
    durationMinutes: Int?,
    ruleEdit: SeriesRuleEdit,
    splitsSeries: Boolean,
    isAllDay: Boolean,
    timeZoneId: String?,
    storedZone: TimeZone
): Result<Pair<Long, Long>> {
    val editZone = seriesTimeZone(timeZoneId, isAllDay)
    // A slot copies the new start's time of day, already whole seconds.
    // With no new start the stored start is kept as is, even with millis
    // from an older version or another app: rewriting it would orphan
    // detached occurrences keyed at those millis (#165).
    val shiftedStart = if (targetStart != null) {
        SplitShift.of(referenceMillis, targetStart, editZone, isAllDay).slot(baseMillis)
    } else {
        baseMillis
    }
    val keptRule = (ruleEdit as? SeriesRuleEdit.Keep)?.rule
    if (targetStart != null && keptRule != null) {
        val refusal = when {
            // iOS can't split a series whose rule pins days at an occurrence
            // moved to another day: EventKit detaches it instead (#194).
            // Refused on both platforms until it can.
            splitsSeries && RruleString.pinsDays(keptRule) &&
                !sameCalendarDay(referenceMillis, storedZone, targetStart, editZone) ->
                "start moves a thisAndFollowing split onto another day, but " +
                    "the series' recurrence rule pins specific days. Pass a " +
                    "recurrenceRule to specify the new pattern."
            leavesRule(
                keptRule,
                referenceMillis = referenceMillis,
                referenceZone = storedZone,
                baseMillis = baseMillis,
                targetStart = targetStart,
                shiftedStart = shiftedStart,
                tz = editZone
            ) ->
                "start moves this series onto a day its recurrence " +
                    "rule doesn't generate. Pass a recurrenceRule to " +
                    "specify the new pattern."
            else -> null
        }
        if (refusal != null) {
            return Result.failure(
                CalendarException(PlatformExceptionCodes.INVALID_ARGUMENTS, refusal)
            )
        }
    }
    val newStart = when (ruleEdit) {
        is SeriesRuleEdit.Keep, SeriesRuleEdit.Clear -> shiftedStart
        // A rule re-anchor moves the series anyway, so it drops any stored
        // millis too, like every event time the plugin writes (#165).
        is SeriesRuleEdit.Replace ->
            RecurrenceAnchor.firstMatch(ruleEdit.rule, shiftedStart, editZone)?.let(::wholeSeconds)
                ?: return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.INVALID_ARGUMENTS,
                        "recurrenceRule generates no occurrences within five years of the anchor"
                    )
                )
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
 * Whether a start move leaves [rule]'s days: either move lands on another
 * day, read in the post-edit zone [tz], that the rule doesn't generate
 * ([RecurrenceAnchor.generates]). The occurrence at [referenceMillis] to
 * [targetStart] guards the caller's intent; the reference is read in
 * [referenceZone], its stored frame, so an all-day toggle onto another
 * local day is a day move. The series start [baseMillis] to [shiftedStart]
 * guards against the #140 orphan. iOS's counterpart is
 * `SeriesDates.leavesRule`.
 */
private fun leavesRule(
    rule: String,
    referenceMillis: Long,
    referenceZone: TimeZone,
    baseMillis: Long,
    targetStart: Long,
    shiftedStart: Long,
    tz: TimeZone
): Boolean {
    fun movesOffRule(from: Long, fromZone: TimeZone, to: Long) =
        !sameCalendarDay(from, fromZone, to, tz) && !RecurrenceAnchor.generates(rule, to, tz)
    // Both checks are needed, even though they repeat each other when the
    // reference is the base. On a {Mon,Tue,Fri} series starting Monday,
    // moving Friday to Saturday shifts the start to Tuesday, which the rule
    // generates: only the first check refuses it. Moving Monday to Tuesday
    // shifts a Friday start to Saturday: only the second does (#140).
    return movesOffRule(referenceMillis, referenceZone, targetStart) ||
        movesOffRule(baseMillis, tz, shiftedStart)
}

/** Whether [a] read in [aZone] falls on the same calendar date as [b] in [bZone]. */
private fun sameCalendarDay(a: Long, aZone: TimeZone, b: Long, bZone: TimeZone): Boolean {
    val ac = Calendar.getInstance(aZone).apply { timeInMillis = a }
    val bc = Calendar.getInstance(bZone).apply { timeInMillis = b }
    return ac.get(Calendar.YEAR) == bc.get(Calendar.YEAR) &&
        ac.get(Calendar.DAY_OF_YEAR) == bc.get(Calendar.DAY_OF_YEAR)
}

/**
 * The caller's new series start brought into the stored frame, or null when
 * there is no new start.
 *
 * [newStartMillis] is a local instant (a Dart DateTime) meant in
 * [deviceZone]; an all-day series is stored as UTC midnight, so it becomes
 * that via [storageMillis], as updateEvent does, and the anchor shift in
 * [resolveSeriesTimes] then compares like with like on either side of UTC
 * (#144). [effectiveIsAllDay] is the series' frame after the edit.
 */
internal fun resolveTargetStart(
    newStartMillis: Long?,
    effectiveIsAllDay: Boolean,
    deviceZone: TimeZone = TimeZone.getDefault()
): Long? = newStartMillis?.let { storageMillis(it, effectiveIsAllDay, deviceZone) }
