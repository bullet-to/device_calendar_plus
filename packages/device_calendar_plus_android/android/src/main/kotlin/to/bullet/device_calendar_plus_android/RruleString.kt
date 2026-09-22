package to.bullet.device_calendar_plus_android

/**
 * The one place that knows the shape of an RRULE string: an optional
 * `RRULE:` prefix, then `KEY=VALUE` parts joined by `;`. Every reader and
 * writer of a rule's parts goes through here so the grammar can't drift
 * between them.
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

    /**
     * [rrule] with any COUNT or UNTIL replaced by [endPart] (e.g. `COUNT=3`),
     * appended last. The other parts are kept as written.
     */
    fun withEnd(rrule: String, endPart: String): String {
        val parts = body(rrule).split(";").filter {
            val key = it.substringBefore('=').trim().uppercase()
            it.isNotBlank() && key != "COUNT" && key != "UNTIL"
        }
        return (parts + endPart).joinToString(";")
    }
}
