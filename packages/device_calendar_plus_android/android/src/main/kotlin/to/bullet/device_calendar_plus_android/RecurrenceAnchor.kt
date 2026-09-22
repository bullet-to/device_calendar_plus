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
        val bySetPos: List<Int>,
        val weekStart: Int
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
     * anchor returns [fromMillis] unchanged. Null when the rule can't be
     * parsed or generates nothing within five years, in which case the caller
     * leaves the anchor alone.
     */
    fun firstMatch(rrule: String, fromMillis: Long, tz: TimeZone): Long? {
        val rule = parse(rrule) ?: return null
        val cal = Calendar.getInstance(tz).apply { timeInMillis = fromMillis }
        val matcher = Matcher(rule, cal)
        repeat(MAX_LOOKAHEAD_DAYS) {
            if (matcher.generates(cal)) return cal.timeInMillis
            // Whole-day steps keep the wall-clock time across DST (mirrors
            // shiftDate).
            cal.add(Calendar.DAY_OF_MONTH, 1)
        }
        return null
    }

    private fun parse(rrule: String): Rule? {
        val body = if (rrule.startsWith("RRULE:")) rrule.substring(6) else rrule
        val params = body.split(";").mapNotNull { part ->
            val idx = part.indexOf('=')
            if (idx <= 0) {
                null
            } else {
                part.substring(0, idx).trim().uppercase() to part.substring(idx + 1).trim()
            }
        }.toMap()
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
            bySetPos = ints("BYSETPOS"),
            weekStart = weekdayCodes[params["WKST"]?.uppercase()] ?: Calendar.MONDAY
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
     * Decides whether a day is in the rule's set for the period (week, month,
     * year) containing it. The period's set is built once and cached, since
     * [firstMatch] visits its days in order.
     */
    private class Matcher(private val rule: Rule, anchor: Calendar) {
        private val anchorWeekday = anchor.get(Calendar.DAY_OF_WEEK)
        private val anchorDayOfMonth = anchor.get(Calendar.DAY_OF_MONTH)
        private val anchorMonth = anchor.get(Calendar.MONTH) + 1
        private var cachedPeriod: Int? = null
        private var cachedDays: Set<Int> = emptySet()

        fun generates(day: Calendar): Boolean {
            val period = periodKey(day)
            if (period != cachedPeriod) {
                cachedPeriod = period
                cachedDays = applySetPos(periodDays(day))
            }
            return dayKey(day) in cachedDays
        }

        /** BYSETPOS keeps only the listed positions (1-based; negative from the end). */
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
            Freq.DAILY -> dayKey(day)
            Freq.WEEKLY -> dayKey(weekStart(day))
            Freq.MONTHLY -> day.get(Calendar.YEAR) * 100 + day.get(Calendar.MONTH)
            Freq.YEARLY -> day.get(Calendar.YEAR)
        }

        /** The first day of the week (per WKST) containing [day], at its time. */
        private fun weekStart(day: Calendar): Calendar {
            val c = day.clone() as Calendar
            val back = (c.get(Calendar.DAY_OF_WEEK) - rule.weekStart + 7) % 7
            c.add(Calendar.DAY_OF_MONTH, -back)
            return c
        }

        private fun periodDays(day: Calendar): Set<Int> = when (rule.freq) {
            Freq.DAILY -> if (passesDailyFilters(day)) setOf(dayKey(day)) else emptySet()
            Freq.WEEKLY -> weekDays(day)
            Freq.MONTHLY -> if (inByMonth(day)) monthDays(day) else emptySet()
            Freq.YEARLY -> yearDays(day)
        }

        /** In a DAILY rule every BYxxx part only filters (no ordinals apply). */
        private fun passesDailyFilters(day: Calendar): Boolean {
            if (!inByMonth(day)) return false
            val dom = day.get(Calendar.DAY_OF_MONTH)
            val length = day.getActualMaximum(Calendar.DAY_OF_MONTH)
            if (rule.byMonthDay.isNotEmpty() && !matchesMonthDay(dom, length)) return false
            val weekday = day.get(Calendar.DAY_OF_WEEK)
            return rule.byDay.isEmpty() || rule.byDay.any { it.weekday == weekday }
        }

        /** The days of [day]'s year the rule generates. */
        private fun yearDays(day: Calendar): Set<Int> {
            // BYDAY on its own: ordinals count within the year ("the 20th
            // Monday"). Once BYMONTH or BYMONTHDAY narrows the set, they count
            // within the month, and the yearly set is the listed months' sets.
            if (rule.byMonth.isEmpty() && rule.byMonthDay.isEmpty() && rule.byDay.isNotEmpty()) {
                val c = (day.clone() as Calendar).apply { set(Calendar.DAY_OF_YEAR, 1) }
                val yearLength = c.getActualMaximum(Calendar.DAY_OF_YEAR)
                val days = mutableSetOf<Int>()
                for (doy in 1..yearLength) {
                    c.set(Calendar.DAY_OF_YEAR, doy)
                    val nth = Nth((doy - 1) / 7 + 1, -((yearLength - doy) / 7 + 1))
                    if (matchesByDay(c, nth)) days += dayKey(c)
                }
                return days
            }
            val months = if (rule.byMonth.isEmpty()) listOf(anchorMonth) else rule.byMonth
            val days = mutableSetOf<Int>()
            for (month in months) {
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
                // otherwise; with neither, the anchor's own day-of-month.
                val included = when {
                    rule.byMonthDay.isNotEmpty() ->
                        matchesMonthDay(dom, length) &&
                            (rule.byDay.isEmpty() || matchesByDay(c, nthInMonth(dom, length)))
                    rule.byDay.isNotEmpty() -> matchesByDay(c, nthInMonth(dom, length))
                    else -> dom == anchorDayOfMonth
                }
                if (included) days += dayKey(c)
            }
            return days
        }

        private fun matchesMonthDay(dom: Int, monthLength: Int): Boolean =
            rule.byMonthDay.any { it == dom || (it < 0 && monthLength + 1 + it == dom) }

        /** A day's weekday ordinal within its period, counted from the start and the end. */
        private data class Nth(val fromStart: Int, val fromEnd: Int)

        private fun nthInMonth(dom: Int, monthLength: Int) =
            Nth((dom - 1) / 7 + 1, -((monthLength - dom) / 7 + 1))

        /** BYDAY membership: the weekday, and the ordinal when one is given. */
        private fun matchesByDay(c: Calendar, nth: Nth): Boolean {
            val weekday = c.get(Calendar.DAY_OF_WEEK)
            return rule.byDay.any {
                it.weekday == weekday &&
                    (it.ordinal == 0 || it.ordinal == nth.fromStart || it.ordinal == nth.fromEnd)
            }
        }

        private fun weekDays(day: Calendar): Set<Int> {
            val weekdays = if (rule.byDay.isEmpty()) {
                setOf(anchorWeekday)
            } else {
                rule.byDay.map { it.weekday }.toSet()
            }
            val c = weekStart(day)
            val days = mutableSetOf<Int>()
            repeat(7) {
                if (c.get(Calendar.DAY_OF_WEEK) in weekdays && inByMonth(c)) days += dayKey(c)
                c.add(Calendar.DAY_OF_MONTH, 1)
            }
            return days
        }

        private fun inByMonth(c: Calendar): Boolean =
            rule.byMonth.isEmpty() || (c.get(Calendar.MONTH) + 1) in rule.byMonth
    }
}
