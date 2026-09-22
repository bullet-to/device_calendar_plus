package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

/**
 * Picks the anchor (DTSTART) for a series whose recurrence rule is being
 * replaced.
 *
 * RFC 5545 wants DTSTART to be a day the RRULE generates, and both Android's
 * Calendar Provider and iOS EventKit treat one that isn't as an extra first
 * occurrence — the orphaned Saturday of #140. [firstMatch] walks forward from
 * the intended anchor to the first day the rule generates, so the anchor of a
 * series switched to a new pattern lands on that pattern. iOS's counterpart is
 * `RecurrenceAnchor.swift`; the two must agree.
 *
 * Covers the RRULE subset the plugin models: FREQ, BYDAY (with ordinals),
 * BYMONTHDAY, BYMONTH, and BYSETPOS on monthly and yearly rules. INTERVAL and
 * WKST don't affect which days a rule can generate from a given anchor (the
 * anchor itself fixes the interval's phase), and a BYSETPOS on a daily or
 * weekly rule is outside the modelled subset, so all three are ignored.
 */
internal object RecurrenceAnchor {
    private enum class Freq { DAILY, WEEKLY, MONTHLY, YEARLY }

    /** One BYDAY entry: [weekday] is a `Calendar.DAY_OF_WEEK`, [ordinal] 0 = every. */
    private data class ByDay(val ordinal: Int, val weekday: Int)

    private data class Rule(
        val freq: Freq,
        val byDay: List<ByDay>,
        val byMonthDay: List<Int>,
        val byMonth: List<Int>,
        val bySetPos: List<Int>
    )

    private val weekdayCodes = mapOf(
        "SU" to Calendar.SUNDAY, "MO" to Calendar.MONDAY, "TU" to Calendar.TUESDAY,
        "WE" to Calendar.WEDNESDAY, "TH" to Calendar.THURSDAY, "FR" to Calendar.FRIDAY,
        "SA" to Calendar.SATURDAY
    )

    /** Five years: enough for a rule pinned to 29 February. */
    private const val MAX_LOOKAHEAD_DAYS = 5 * 366

    /**
     * The first instant on or after [fromMillis] whose calendar day (in [tz])
     * the rule generates, at [fromMillis]'s wall-clock time. Parts the rule
     * leaves implicit (no BYDAY, BYMONTHDAY or BYMONTH) come from [fromMillis]
     * itself, as they would from DTSTART — so a rule that already fits its
     * anchor returns [fromMillis] unchanged — as does a rule outside the
     * modelled subset (no FREQ this object knows), which is assumed to fit
     * its anchor. Null when the rule generates nothing within five years, so
     * the caller can refuse rather than anchor the series off-rule.
     */
    fun firstMatch(rrule: String, fromMillis: Long, tz: TimeZone): Long? {
        val cal = Calendar.getInstance(tz).apply { timeInMillis = fromMillis }
        val rule = parse(rrule)?.impliedBy(cal) ?: return fromMillis
        val matcher = Matcher(rule)
        repeat(MAX_LOOKAHEAD_DAYS) {
            if (matcher.generates(cal)) return cal.timeInMillis
            // Whole-day steps keep the wall-clock time across DST (mirrors
            // shiftDate).
            cal.add(Calendar.DAY_OF_MONTH, 1)
        }
        return null
    }

    private fun parse(rrule: String): Rule? {
        val params = RruleString.params(rrule)
        val freq = when (params["FREQ"]?.uppercase()) {
            "DAILY" -> Freq.DAILY
            "WEEKLY" -> Freq.WEEKLY
            "MONTHLY" -> Freq.MONTHLY
            "YEARLY" -> Freq.YEARLY
            else -> return null
        }
        fun ints(key: String): List<Int> =
            params[key]?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: emptyList()
        val byDay = params["BYDAY"]?.split(",")
            ?.mapNotNull { parseByDay(it.trim().uppercase()) } ?: emptyList()
        return Rule(
            freq = freq,
            byDay = byDay,
            byMonthDay = ints("BYMONTHDAY"),
            byMonth = ints("BYMONTH"),
            bySetPos = ints("BYSETPOS")
        )
    }

    /** "TU", "2TU", "-1FR", "+1MO". */
    private fun parseByDay(value: String): ByDay? {
        if (value.length < 2) return null
        val weekday = weekdayCodes[value.takeLast(2)] ?: return null
        val prefix = value.dropLast(2)
        val ordinal = if (prefix.isEmpty()) 0 else (prefix.toIntOrNull() ?: return null)
        return ByDay(ordinal, weekday)
    }

    /**
     * Fills in the parts the rule leaves implicit from [anchor], as RFC 5545
     * fills them from DTSTART: a WEEKLY rule with no BYDAY runs on the
     * anchor's weekday, a MONTHLY rule with neither BYDAY nor BYMONTHDAY on
     * its day of the month, and a YEARLY rule likewise, in the anchor's month
     * unless BYMONTH lists its own. The one YEARLY form left alone is BYDAY on
     * its own, whose ordinals count within the year. A DAILY rule has nothing
     * implicit: each of its parts only filters.
     */
    private fun Rule.impliedBy(anchor: Calendar): Rule {
        val weekday = anchor.get(Calendar.DAY_OF_WEEK)
        val dayOfMonth = listOf(anchor.get(Calendar.DAY_OF_MONTH))
        val month = listOf(anchor.get(Calendar.MONTH) + 1)
        val ownDay = byDay.isEmpty() && byMonthDay.isEmpty()
        return when (freq) {
            Freq.DAILY -> this
            // A WEEKLY rule ignores BYMONTHDAY.
            Freq.WEEKLY -> copy(
                byDay = byDay.ifEmpty { listOf(ByDay(0, weekday)) },
                byMonthDay = emptyList()
            )
            Freq.MONTHLY -> if (ownDay) copy(byMonthDay = dayOfMonth) else this
            Freq.YEARLY ->
                if (byMonth.isEmpty() && byMonthDay.isEmpty() && byDay.isNotEmpty()) {
                    this
                } else {
                    copy(
                        byMonth = byMonth.ifEmpty { month },
                        byMonthDay = if (ownDay) dayOfMonth else byMonthDay
                    )
                }
        }
    }

    /**
     * Decides whether a day is in the rule's set for the period containing
     * it. A monthly or yearly period's set is built once and cached, since
     * [firstMatch] visits its days in order; the rule must already have had
     * its implicit parts filled in ([impliedBy]).
     */
    private class Matcher(private val rule: Rule) {
        private var cachedPeriod: Int? = null
        private var cachedDays: Set<Int> = emptySet()

        fun generates(day: Calendar): Boolean = when (rule.freq) {
            // Daily and weekly rules are decided a day at a time: whether a
            // day is in a weekly set doesn't depend on where the week starts.
            Freq.DAILY, Freq.WEEKLY -> dayPasses(day)
            Freq.MONTHLY, Freq.YEARLY -> {
                val period = periodKey(day)
                if (period != cachedPeriod) {
                    cachedPeriod = period
                    cachedDays = periodDays(day)
                }
                dayKey(day) in cachedDays
            }
        }

        /**
         * BYSETPOS keeps only the listed positions of a month's or year's set
         * (1-based; negative from the end).
         */
        private fun applySetPos(days: Set<Int>): Set<Int> {
            if (rule.bySetPos.isEmpty()) return days
            val ordered = days.sorted()
            return rule.bySetPos.mapNotNull { pos ->
                val index = if (pos > 0) pos - 1 else ordered.size + pos
                ordered.getOrNull(index)
            }.toSet()
        }

        private fun dayKey(c: Calendar): Int =
            c.get(Calendar.YEAR) * 1000 + c.get(Calendar.DAY_OF_YEAR)

        private fun periodKey(day: Calendar): Int = when (rule.freq) {
            Freq.MONTHLY -> day.get(Calendar.YEAR) * 100 + day.get(Calendar.MONTH)
            else -> day.get(Calendar.YEAR)
        }

        private fun periodDays(day: Calendar): Set<Int> = when (rule.freq) {
            Freq.MONTHLY -> if (inByMonth(day)) applySetPos(monthDays(day)) else emptySet()
            else -> applySetPos(yearDays(day))
        }

        /**
         * In a DAILY or WEEKLY rule every BYxxx part only filters (no
         * ordinals apply).
         */
        private fun dayPasses(day: Calendar): Boolean {
            if (!inByMonth(day)) return false
            val dom = day.get(Calendar.DAY_OF_MONTH)
            val length = day.getActualMaximum(Calendar.DAY_OF_MONTH)
            if (rule.byMonthDay.isNotEmpty() && !matchesMonthDay(dom, length)) return false
            val weekday = day.get(Calendar.DAY_OF_WEEK)
            return rule.byDay.isEmpty() || rule.byDay.any { it.weekday == weekday }
        }

        /** The days of [day]'s year the rule generates. */
        private fun yearDays(day: Calendar): Set<Int> {
            // BYDAY on its own (the one form impliedBy leaves without a
            // BYMONTH): ordinals count within the year ("the 20th Monday").
            // Otherwise they count within the month, and the yearly set is
            // the listed months' sets.
            if (rule.byMonth.isEmpty()) {
                val c = (day.clone() as Calendar).apply { set(Calendar.DAY_OF_YEAR, 1) }
                val yearLength = c.getActualMaximum(Calendar.DAY_OF_YEAR)
                val days = mutableSetOf<Int>()
                for (doy in 1..yearLength) {
                    c.set(Calendar.DAY_OF_YEAR, doy)
                    if (matchesByDay(c, nthInPeriod(doy, yearLength))) days += dayKey(c)
                }
                return days
            }
            val days = mutableSetOf<Int>()
            for (month in rule.byMonth) {
                if (month !in 1..12) continue
                val inMonth = (day.clone() as Calendar).apply {
                    set(Calendar.DAY_OF_MONTH, 1)
                    set(Calendar.MONTH, month - 1)
                }
                days += monthDays(inMonth)
            }
            return days
        }

        /** The days of [day]'s month the rule generates. */
        private fun monthDays(day: Calendar): Set<Int> {
            val first = (day.clone() as Calendar).apply { set(Calendar.DAY_OF_MONTH, 1) }
            val length = first.getActualMaximum(Calendar.DAY_OF_MONTH)
            val days = mutableSetOf<Int>()
            val c = first.clone() as Calendar
            for (dom in 1..length) {
                c.set(Calendar.DAY_OF_MONTH, dom)
                // Per RFC 5545, BYDAY limits a BYMONTHDAY set and expands
                // otherwise (impliedBy guarantees one of the two is present).
                val included = if (rule.byMonthDay.isNotEmpty()) {
                    matchesMonthDay(dom, length) &&
                        (rule.byDay.isEmpty() || matchesByDay(c, nthInPeriod(dom, length)))
                } else {
                    matchesByDay(c, nthInPeriod(dom, length))
                }
                if (included) days += dayKey(c)
            }
            return days
        }

        private fun matchesMonthDay(dom: Int, monthLength: Int): Boolean =
            rule.byMonthDay.any { it == dom || (it < 0 && monthLength + 1 + it == dom) }

        /** A day's weekday ordinal within its period, counted from the start and the end. */
        private data class Nth(val fromStart: Int, val fromEnd: Int)

        /**
         * The ordinal of the day at [position] (1-based) in a period of
         * [periodLength] days: which length is passed decides whether "2MO"
         * counts within the month or within the year.
         */
        private fun nthInPeriod(position: Int, periodLength: Int) =
            Nth((position - 1) / 7 + 1, -((periodLength - position) / 7 + 1))

        /** BYDAY membership: the weekday, and the ordinal when one is given. */
        private fun matchesByDay(c: Calendar, nth: Nth): Boolean {
            val weekday = c.get(Calendar.DAY_OF_WEEK)
            return rule.byDay.any {
                it.weekday == weekday &&
                    (it.ordinal == 0 || it.ordinal == nth.fromStart || it.ordinal == nth.fromEnd)
            }
        }

        private fun inByMonth(c: Calendar): Boolean =
            rule.byMonth.isEmpty() || (c.get(Calendar.MONTH) + 1) in rule.byMonth
    }
}
