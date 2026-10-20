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
 * Whole 24h days from [fromMillis] to [toMillis], read on the wall clock in
 * [tz] and truncated toward zero: -1d+9h is 0 days, +1d+1h is 1. Read on
 * the wall clock rather than raw, so a DST change between the two doesn't
 * turn a whole-day move into a day less. That DST case follows Android's
 * calendar-day count from before #224 and hasn't been checked against
 * EventKit.
 */
private fun wholeWallClockDaysBetween(fromMillis: Long, toMillis: Long, tz: TimeZone): Int =
    (((toMillis + tz.getOffset(toMillis)) - (fromMillis + tz.getOffset(fromMillis))) /
        AllDayDates.MILLIS_PER_DAY).toInt()

/**
 * A series' anchor moved from one instant to another, as a rule for moving
 * the rest of the series with it: its slots by the whole calendar days the
 * anchor moved, and its detached occurrences' starts by the whole 24h
 * wall-clock days in the anchor's shift, both counted in the series' time
 * zone [tz] (see [seriesTimeZone]). Not by the raw millisecond shift, which
 * a DST change between the anchor and a later date would put an hour off.
 * The anchor-shift that lets [EventsService.updateRecurring] move both the
 * time and the day of a series (#103), and where a `thisAndFollowing`
 * split carries what it carries (#158); iOS's counterparts are
 * `SeriesDates.shiftStart` and EKSpan.futureEvents.
 *
 * [slot] is where a stored slot lands on the moved series: brought into
 * the frame after the edit ([FrameChange], for an all-day toggle), then
 * that many days on, at the new anchor's wall-clock time of day (midnight
 * for all-day, which is stored as UTC midnight). [start] is where a
 * detached occurrence's own start goes: on by [startDayDelta] days, at its
 * own time of day, in its own frame (the occurrence keeps its own all-day
 * flag).
 *
 * The two day counts differ only when a timed series' anchor changes its
 * time of day too. EventKit moves a detached occurrence by the whole 24h
 * days in the anchor's shift, not by the calendar days: a +1h shift from
 * 23:30 to 00:30 the next day moves the slots a day but leaves the
 * occurrence where it is, and a +25h one moves it a day (#224). So
 * [startDayDelta] is the anchor's wall-clock shift in whole days
 * ([wholeWallClockDaysBetween]). A move that keeps the time of day and an
 * all-day series (midnight on both sides) come out at the calendar days
 * either way.
 *
 * EventKit also pairs the kept occurrence with the slot before its own on
 * such a shift (it skips occurrence 5's slot, not occurrence 6's, for
 * occurrence 6): Android doesn't copy that, and pairs it with its own
 * slot, [slot] (#224).
 */
internal class SplitShift private constructor(
    private val frameChange: FrameChange,
    private val slotDayDelta: Int,
    private val startDayDelta: Int,
    private val tz: TimeZone,
    private val hour: Int,
    private val minute: Int,
    private val second: Int,
    private val millisecond: Int,
) {

    /**
     * [old], a stored instant of the series, in the frame after the edit,
     * moved by the anchor's days, at the new anchor's time of day.
     */
    fun slot(old: Long): Long {
        val cal = addDays(frameChange.convert(old), slotDayDelta)
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, second)
        cal.set(Calendar.MILLISECOND, millisecond)
        return cal.timeInMillis
    }

    /**
     * [old], a detached occurrence's own start, moved by the whole days in
     * the anchor's shift ([startDayDelta]), keeping its own time of day.
     */
    fun start(old: Long): Long = addDays(old, startDayDelta).timeInMillis

    private fun addDays(millis: Long, days: Int): Calendar =
        Calendar.getInstance(tz).apply {
            timeInMillis = millis
            add(Calendar.DAY_OF_YEAR, days)
        }

    companion object {
        /**
         * The shift that moves the anchor [fromAnchor] to [toAnchor], in
         * the series' time zone [tz]. [fromAnchor] is a stored instant,
         * brought into [toAnchor]'s frame by [frameChange] before the days
         * are counted, so the anchor and every slot [slot] moves are read in
         * the one frame (#186). All-day series shift by whole days
         * with the time of day left at midnight; timed ones carry the full
         * wall-clock time of day (down to millis) from [toAnchor], matching
         * iOS's shiftStart so the platforms agree. Callers pass whole-second
         * anchors (floored at the plugin seam or by [resolveSeriesTimes],
         * #165), so the millisecond carried is 0 in practice; it is still
         * set so [slot] clears the millis of the start it moves.
         */
        fun of(
            fromAnchor: Long,
            toAnchor: Long,
            tz: TimeZone,
            isAllDay: Boolean,
            frameChange: FrameChange,
        ): SplitShift {
            val target = Calendar.getInstance(tz).apply { timeInMillis = toAnchor }
            val from = frameChange.convert(fromAnchor)
            val slotDayDelta = calendarDaysBetween(from, toAnchor, tz)
            // See [FrameChange.hasComparableTimeOfDay].
            val startDayDelta = if (frameChange.hasComparableTimeOfDay) {
                wholeWallClockDaysBetween(from, toAnchor, tz)
            } else {
                slotDayDelta
            }
            return SplitShift(
                frameChange = frameChange,
                slotDayDelta = slotDayDelta,
                startDayDelta = startDayDelta,
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
 * the row's stored frame [storedZone]; [SeriesTimeEdit.frameChange]
 * brings them into the post-edit frame too, keeping their dates, and the
 * shift reads all three in the one post-edit zone,
 * `seriesTimeZone(timeZoneId, isAllDay)` ([isAllDay] is the series' all-day
 * state after the edit). So the day delta is counted in the local days
 * EventKit counts even when a DST change falls between them, whichever way
 * an all-day toggle goes (#186).
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
 *
 * [SeriesTimes.carry] is the shift that moved the anchor to the new start,
 * in that same frame: where a `thisAndFollowing` split's detached
 * occurrences land on the new series (#158), so they and the anchor are
 * moved by one shift, read in one frame.
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
): Result<SeriesTimes> {
    val targetStart = timeEdit.targetStart
    val editZone = seriesTimeZone(timeZoneId, isAllDay)
    // Base and reference are read in the frame the target is in. Read in
    // the other frame's zone, a DST change between them could put one on
    // another date and not the other, and the start moved a day further
    // than the occurrence did (#186, #208). With no new start nothing
    // moves, and the start stays in its stored frame.
    val frameChange = if (targetStart != null) timeEdit.frameChange else FrameChange.None
    // A slot copies the new start's time of day, already whole seconds.
    // With no new start the stored start is kept as is, even with millis
    // from an older version or another app: rewriting it would orphan
    // detached occurrences keyed at those millis (#165).
    val shiftedStart = if (targetStart != null) {
        SplitShift.of(referenceMillis, targetStart, editZone, isAllDay, frameChange)
            .slot(baseMillis)
    } else {
        baseMillis
    }
    val keptRule = (ruleEdit as? SeriesRuleEdit.Keep)?.rule
    if (targetStart != null && keptRule != null &&
        leavesRule(
            keptRule,
            storedReference = referenceMillis,
            storedZone = storedZone,
            frameBase = frameChange.convert(baseMillis),
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
    val newDurationMs = if (timeEdit.durationMillis != null) {
        timeEdit.durationMillis
    } else {
        // Always floored, so the written duration is whole seconds (the
        // recurring path writes DURATION in seconds anyway). The end written
        // from it is whole only when the start is: a millis start nothing
        // moves is kept, so its end keeps those millis too (#165).
        wholeSeconds(existingDurationMillis)
    }
    // To the final start, so a rule re-anchor's move is carried too.
    val carry = SplitShift.of(referenceMillis, newStart, editZone, isAllDay, frameChange)
    return Result.success(SeriesTimes(newStart, newDurationMs, carry))
}

/** What [resolveSeriesTimes] resolves a series edit to. */
internal data class SeriesTimes(
    /** The new series start, in the frame after the edit. */
    val start: Long,
    /** The new duration, in whole seconds. */
    val durationMillis: Long,
    /**
     * The shift that took the anchor to [start]: where the series' detached
     * occurrences go ([DetachedOccurrenceCarry.settleAfterSplit],
     * [DetachedOccurrenceCarry.settleInPlace]).
     */
    val carry: SplitShift,
)

/**
 * Whether a start move leaves [rule]'s days: either move lands on another
 * day, read in the post-edit zone [tz], that the rule doesn't generate
 * ([RecurrenceAnchor.generates]).
 *
 * The two moves take their starting points in different frames, on
 * purpose:
 * - The occurrence at [storedReference] to [targetStart] guards the
 *   caller's intent. [storedReference] is the occurrence as stored, NOT
 *   brought into the edit frame, and is read in [storedZone]: so an all-day
 *   toggle onto another local day counts as a day move. Passing it
 *   converted would quietly lose that check.
 * - The series start [frameBase] to [shiftedStart] guards against the #140
 *   orphan. [frameBase] is the start already brought into the edit frame
 *   ([FrameChange]), read in [tz] like [shiftedStart].
 *
 * iOS's counterpart is `SeriesDates.leavesRule`.
 */
private fun leavesRule(
    rule: String,
    storedReference: Long,
    storedZone: TimeZone,
    frameBase: Long,
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
    return movesOffRule(storedReference, storedZone, targetStart) ||
        movesOffRule(frameBase, tz, shiftedStart)
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
    val durationMillis: Long?,
    /** Whether [targetStart] is a default rather than the caller's `start`. */
    val startDefaulted: Boolean,
    /** How a stored instant of the series reaches the frame [targetStart] is in. */
    val frameChange: FrameChange,
) {
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
 * through. An edit that changes the all-day flag carries the
 * [FrameChange] its stored instants take, and fills in what the caller
 * left out, as EventKit does:
 * - A toggle of a timed series to all-day ([rowAllDay] false,
 *   [patchIsAllDay] true): `start` defaults to [defaultStart], the named
 *   occurrence's own start (the master's when the edit names the master).
 *   [resolveSeriesTimes] counts the move from that occurrence in local
 *   days, so a series edit keeps its start's local date. `duration`
 *   defaults to the whole [deviceZone] days that the master covers
 *   ([allDayToggleDurationMinutes]): the occurrence starting at
 *   [masterStart] and lasting [durationMillis], on a whole-series edit and
 *   a split alike.
 * - A toggle of an all-day series to timed: `start` defaults to
 *   [defaultStart] in the timed frame, local midnight of its date, and
 *   `duration` to the master's [AllDayDates.timedSpan], through the last
 *   second of its last date.
 *
 * EventKit floats the master's own dates either way, and a split's new
 * series keeps the master's span. Without these defaults the stored
 * DTSTART and DURATION stayed under the other ALL_DAY: a toggle to all-day
 * read back on the wrong date or collapsed (#124), and a toggle to timed
 * read back the evening before west of UTC (#219). Spanning the named
 * occurrence instead differed from EventKit wherever a DST change moved
 * that occurrence across a local midnight the master doesn't cross, on a
 * whole-series edit (#208) and on a split (#221).
 */
internal fun resolveSeriesTimeEdit(
    newStartMillis: Long?,
    durationMinutes: Int?,
    rowAllDay: Boolean,
    patchIsAllDay: Boolean?,
    defaultStart: Long,
    masterStart: Long,
    durationMillis: Long,
    deviceZone: TimeZone = TimeZone.getDefault()
): SeriesTimeEdit {
    val frameChange = FrameChange.of(rowAllDay, patchIsAllDay, deviceZone)
    val effectiveIsAllDay = patchIsAllDay ?: rowAllDay
    val givenDuration = durationMinutes?.let { it * 60_000L }
    val (start, duration) = when (frameChange) {
        FrameChange.None -> newStartMillis to givenDuration
        is FrameChange.ToAllDay -> (newStartMillis ?: defaultStart) to (
            givenDuration ?: allDayToggleDurationMinutes(
                masterStart, durationMillis, deviceZone
            ) * 60_000L
            )
        is FrameChange.ToTimed -> {
            val (from, to) = AllDayDates.timedSpan(masterStart, durationMillis, deviceZone)
            (newStartMillis ?: frameChange.convert(defaultStart)) to
                (givenDuration ?: (to - from))
        }
    }
    return SeriesTimeEdit(
        targetStart = resolveTargetStart(start, effectiveIsAllDay, deviceZone),
        durationMillis = duration,
        startDefaulted = newStartMillis == null && frameChange != FrameChange.None,
        frameChange = frameChange,
    )
}

/**
 * The rule the new series of a `thisAndFollowing` split at [splitAt] gets,
 * or null when it doesn't recur: none when [ruleEdit] clears the rule, and
 * [replacedRuleAfterSplit] when it replaces it, [keptRuleAfterSplit] when
 * it keeps the series' own, [existingRule]. Between them they own the COUNT
 * a split gives the new series. [providerCountBefore] is the provider's
 * count of the series' occurrences before the split, the kept rule's
 * fallback.
 */
internal fun newSeriesRule(
    ruleEdit: SeriesRuleEdit,
    existingRule: String,
    seriesStart: Long,
    splitAt: Long,
    tz: TimeZone,
    providerCountBefore: () -> Int,
): String? = when (ruleEdit) {
    SeriesRuleEdit.Clear -> null
    // A new rule's COUNT counts from the series' start, as EventKit counts
    // it; one used up before the split leaves a one-off (#124).
    is SeriesRuleEdit.Replace -> replacedRuleAfterSplit(ruleEdit.rule, seriesStart, splitAt, tz)
    is SeriesRuleEdit.Keep -> keptRuleAfterSplit(existingRule, seriesStart, splitAt, tz, providerCountBefore)
}

/**
 * The rule a `thisAndFollowing` split that keeps the series' rule [rule]
 * gives the new series at [splitAt]: COUNT less the occurrences [rule]
 * generates from [seriesStart] before the split, and at least one, the
 * split occurrence itself. Without the drop the new series would
 * over-generate.
 *
 * The occurrences before the split are counted from the rule
 * ([RecurrenceAnchor.countBefore], in the series' zone [tz]), so deleted
 * ones count too, as RFC 5545 counts COUNT and as EventKit saves the same
 * split. The provider's Instances leave deleted occurrences out, so a series
 * with some before the split once ran past the original's end (#220).
 * [providerCountBefore] is that Instances count, the fallback for a rule
 * [RecurrenceAnchor.countBefore] can't expand; a lambda, so the provider is
 * queried only then. That fallback still leaves deleted occurrences out, so
 * for such a rule (such as BYHOUR, BYWEEKNO, BYYEARDAY or a daily or weekly
 * BYSETPOS) the new series still runs one occurrence past the original's
 * end per deletion before the split. A rule without COUNT is unchanged.
 */
internal fun keptRuleAfterSplit(
    rule: String,
    seriesStart: Long,
    splitAt: Long,
    tz: TimeZone,
    providerCountBefore: () -> Int,
): String {
    val count = RruleString.count(rule) ?: return rule
    val before = RecurrenceAnchor.countBefore(rule, seriesStart, splitAt, tz) ?: providerCountBefore()
    return RruleString.withCount(rule, maxOf(1, count - before))
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
internal fun replacedRuleAfterSplit(rule: String, seriesStart: Long, splitAt: Long, tz: TimeZone): String? {
    val count = RruleString.count(rule) ?: return rule
    // A rule outside the modelled subset can't be expanded, so its COUNT is
    // kept as given.
    val before = RecurrenceAnchor.countBefore(rule, seriesStart, splitAt, tz) ?: return rule
    val left = count - before
    return if (left > 0) RruleString.withCount(rule, left) else null
}
