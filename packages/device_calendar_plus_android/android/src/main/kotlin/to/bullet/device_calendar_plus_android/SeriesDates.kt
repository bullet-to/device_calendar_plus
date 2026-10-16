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
 * the row's stored frame [storedZone]; the shift reads all three in the one
 * post-edit zone, `seriesTimeZone(timeZoneId, isAllDay)` ([isAllDay] is the
 * series' all-day state after the edit). A toggle to all-day
 * ([SeriesTimeEdit.intoEditFrame]) first brings base and reference into that
 * frame too, as the UTC midnights of their device-local dates, so the day
 * delta is counted in the local days EventKit counts even when a DST change
 * falls between them (#186). A toggle off is left as stored: base and
 * reference are then both UTC dates, so the post-edit zone reads them alike
 * and the error cancels out of the day delta.
 *
 * The new start must be a day the series' rule generates, or the provider
 * emits it as an extra first occurrence (#140, #189). [ruleEdit] decides
 * how: a kept rule must generate the days a move lands on ([leavesRule]),
 * or the move fails with INVALID_ARGUMENTS; a replacing rule moves the
 * shifted start onto the first day it generates, keeping its wall-clock
 * time, and fails with INVALID_ARGUMENTS when it generates nothing within
 * five years; a cleared rule needs neither. A time-only move leaves a start
 * the kept rule doesn't generate (one anchored off its rule by another app,
 * or in another zone) where it is. A refusal names what moved the start
 * ([SeriesTimeEdit.mover]). The duration is overridden when [timeEdit]
 * carries one.
 */
internal fun resolveSeriesTimes(
    baseMillis: Long,
    referenceMillis: Long,
    existingDurationMillis: Long,
    timeEdit: SeriesTimeEdit,
    ruleEdit: SeriesRuleEdit,
    isAllDay: Boolean,
    timeZoneId: String?,
    storedZone: TimeZone
): Result<Pair<Long, Long>> {
    val targetStart = timeEdit.targetStart
    val durationMinutes = timeEdit.durationMinutes
    val editZone = seriesTimeZone(timeZoneId, isAllDay)
    // Base and reference in the frame the target is in. Read as timed
    // instants in UTC, a DST change between them could put one on the next
    // UTC date and not the other, and the start moved a day further than
    // the occurrence did (#186, #208).
    val frameBase = timeEdit.intoEditFrame(baseMillis)
    val frameReference = timeEdit.intoEditFrame(referenceMillis)
    // A slot copies the new start's time of day, already whole seconds.
    // With no new start the stored start is kept as is, even with millis
    // from an older version or another app: rewriting it would orphan
    // detached occurrences keyed at those millis (#165).
    val shiftedStart = if (targetStart != null) {
        SplitShift.of(frameReference, targetStart, editZone, isAllDay).slot(frameBase)
    } else {
        baseMillis
    }
    val keptRule = (ruleEdit as? SeriesRuleEdit.Keep)?.rule
    if (targetStart != null && keptRule != null &&
        leavesRule(
            keptRule,
            // The reference stays in its stored frame on purpose: leavesRule
            // reads it in storedZone, so a toggle onto another local day
            // counts as a day move.
            referenceMillis = referenceMillis,
            referenceZone = storedZone,
            baseMillis = frameBase,
            targetStart = targetStart,
            shiftedStart = shiftedStart,
            tz = editZone
        )
    ) {
        return Result.failure(
            CalendarException(
                PlatformExceptionCodes.INVALID_ARGUMENTS,
                "${timeEdit.mover} this series onto a day its recurrence " +
                    "rule doesn't generate. Pass a recurrenceRule to " +
                    "specify the new pattern."
            )
        )
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

/**
 * The duration, in minutes, an occurrence at [startMillis] lasting
 * [durationMillis] takes once an edit toggles its timed series all-day
 * without a `duration`: the [AllDayDates.toggleSpan] of the occurrence, as
 * a series duration (#124).
 */
internal fun allDayToggleDurationMinutes(
    startMillis: Long,
    durationMillis: Long,
    deviceZone: TimeZone = TimeZone.getDefault()
): Int {
    val (firstDay, endEdge) = AllDayDates.toggleSpan(startMillis, durationMillis, deviceZone)
    return ((endEdge - firstDay) / 60_000L).toInt()
}

/** The start and duration a series edit writes, after [resolveSeriesTimeEdit]. */
internal data class SeriesTimeEdit(
    /** The new start in the stored frame ([resolveTargetStart]), or null to keep it. */
    val targetStart: Long?,
    /** The new duration, or null to keep it. */
    val durationMinutes: Int?,
    /** Whether [targetStart] is a default rather than the caller's `start`. */
    val startDefaulted: Boolean,
    /**
     * The device zone whose local dates a toggle of a timed series to
     * all-day keeps, or null when the edit isn't that toggle. Read it
     * through [intoEditFrame].
     */
    val toAllDayFrom: TimeZone? = null,
) {
    /**
     * [millis], a stored instant of the series, in the frame [targetStart]
     * is in: on a toggle to all-day, the UTC midnight of its [toAllDayFrom]
     * local date (#186); otherwise [millis] unchanged.
     */
    fun intoEditFrame(millis: Long): Long =
        toAllDayFrom?.let { AllDayDates.localDateToUtcMidnight(millis, it) } ?: millis

    /** What moved the start, as a refusal of the move names it. */
    val mover: String
        get() = if (startDefaulted) {
            "isAllDay without a start (the occurrence's device-local date) moves"
        } else {
            "start moves"
        }
}

/**
 * The start and duration a series edit writes, with the start brought into
 * the stored frame ([resolveTargetStart]) of the series after the edit.
 *
 * Most edits pass the caller's [newStartMillis] and [durationMinutes]
 * through. A toggle of a timed series to all-day ([rowAllDay] false,
 * [patchIsAllDay] true) fills in what the caller left out:
 * - `start` defaults to [defaultStart], the named occurrence's own start
 *   (the master's when the edit names the master). [resolveSeriesTimes]
 *   counts the move from that occurrence in local days, so a series edit
 *   keeps its start's local date.
 * - `duration` defaults to the whole [deviceZone] days that the first
 *   occurrence of the series after the edit covers
 *   ([allDayToggleDurationMinutes]): the one starting at
 *   [firstOccurrenceStart] and lasting [durationMillis]. That's the master
 *   on a whole-series edit, and the named occurrence a split starts the new
 *   series at.
 *
 * That's what EventKit makes of the same toggle: it floats the master's (or
 * the split occurrence's) own dates. Without these defaults the timed
 * DTSTART and DURATION stayed under ALL_DAY=1, and the series read back on
 * the wrong date or collapsed (#124). Spanning the named occurrence on a
 * whole-series edit differed from EventKit wherever a DST change moved that
 * occurrence across a local midnight the master doesn't cross (#208).
 */
internal fun resolveSeriesTimeEdit(
    newStartMillis: Long?,
    durationMinutes: Int?,
    rowAllDay: Boolean,
    patchIsAllDay: Boolean?,
    defaultStart: Long,
    firstOccurrenceStart: Long,
    durationMillis: Long,
    deviceZone: TimeZone = TimeZone.getDefault()
): SeriesTimeEdit {
    val effectiveIsAllDay = patchIsAllDay ?: rowAllDay
    if (patchIsAllDay != true || rowAllDay) {
        return SeriesTimeEdit(
            targetStart = resolveTargetStart(newStartMillis, effectiveIsAllDay, deviceZone),
            durationMinutes = durationMinutes,
            startDefaulted = false
        )
    }
    return SeriesTimeEdit(
        targetStart = resolveTargetStart(
            newStartMillis ?: defaultStart, effectiveIsAllDay, deviceZone
        ),
        durationMinutes = durationMinutes
            ?: allDayToggleDurationMinutes(firstOccurrenceStart, durationMillis, deviceZone),
        startDefaulted = newStartMillis == null,
        toAllDayFrom = deviceZone,
    )
}

/**
 * The rule a `thisAndFollowing` split that replaces the series' rule with
 * [rule] gives the new series at [splitAt], or null when it leaves the new
 * series nothing to repeat.
 *
 * EventKit counts a new rule's COUNT from the start of the series it splits
 * ([seriesStart]), not from the split: the new series gets COUNT less the
 * occurrences [rule] would have generated before [splitAt]
 * ([RecurrenceAnchor.countBefore], in the series' zone [tz]), and none at
 * all, saved as a one-off, when that leaves nothing. Android honoured the
 * COUNT as given, so the new series ran longer than on iOS (#124). A rule
 * that ends by UNTIL, or not at all, or that [RecurrenceAnchor.countBefore]
 * can't expand, is unchanged.
 */
internal fun splitSeriesRule(rule: String, seriesStart: Long, splitAt: Long, tz: TimeZone): String? {
    val count = RruleString.count(rule) ?: return rule
    // A rule outside the modelled subset can't be expanded, so its COUNT is
    // kept as given.
    val before = RecurrenceAnchor.countBefore(rule, seriesStart, splitAt, tz) ?: return rule
    val left = count - before
    return if (left > 0) RruleString.withCount(rule, left) else null
}
