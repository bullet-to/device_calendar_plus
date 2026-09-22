package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * The one place that knows the shape of an RRULE string: an optional
 * `RRULE:` prefix, then `KEY=VALUE` parts joined by `;`, with COUNT and UNTIL
 * (a UTC date-time, or a date alone for all-day series) as the end. Every
 * reader and writer of a rule's parts goes through here so the grammar can't
 * drift between them; the typed reading of the BYxxx parts is
 * `RecurrenceAnchor`'s.
 */
internal object RruleString {
    private const val PREFIX = "RRULE:"

    /** [rrule] without its `RRULE:` prefix, if it has one. */
    fun body(rrule: String): String =
        if (rrule.startsWith(PREFIX)) rrule.substring(PREFIX.length) else rrule

    /**
     * The rule's parts keyed by their upper-cased name (`BYDAY`, `COUNT`),
     * values trimmed. Empty parts and parts with no `=` are dropped; when a
     * key repeats, the last wins.
     */
    fun params(rrule: String): Map<String, String> =
        body(rrule).split(";").mapNotNull { part ->
            val idx = part.indexOf('=')
            if (idx <= 0) {
                null
            } else {
                part.substring(0, idx).trim().uppercase() to part.substring(idx + 1).trim()
            }
        }.toMap()

    /** The rule's COUNT, or null when it has none. */
    fun count(rrule: String): Int? = params(rrule)["COUNT"]?.toIntOrNull()

    /** [rrule] with any COUNT or UNTIL replaced by COUNT=[count]. */
    fun withCount(rrule: String, count: Int): String = withEnd(rrule, "COUNT=$count")

    /**
     * [rrule] with any COUNT or UNTIL replaced by an inclusive UNTIL at
     * [untilMillis]: a UTC date-time (`20261001T215959Z`), or the date alone
     * when [dateOnly] (all-day series, whose UNTIL carries no time).
     */
    fun withUntil(rrule: String, untilMillis: Long, dateOnly: Boolean): String =
        withEnd(rrule, "UNTIL=${formatUtc(untilMillis, dateOnly)}")

    /**
     * [rrule] with any COUNT or UNTIL replaced by [endPart], appended last.
     * The other parts are kept as written.
     */
    private fun withEnd(rrule: String, endPart: String): String {
        val parts = body(rrule).split(";").filter {
            val key = it.substringBefore('=').trim().uppercase()
            it.isNotBlank() && key != "COUNT" && key != "UNTIL"
        }
        return (parts + endPart).joinToString(";")
    }

    private fun formatUtc(millis: Long, dateOnly: Boolean): String {
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        cal.timeInMillis = millis
        val date = String.format(
            Locale.US,
            "%04d%02d%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH)
        )
        if (dateOnly) return date
        return date + String.format(
            Locale.US,
            "T%02d%02d%02dZ",
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE),
            cal.get(Calendar.SECOND)
        )
    }
}
