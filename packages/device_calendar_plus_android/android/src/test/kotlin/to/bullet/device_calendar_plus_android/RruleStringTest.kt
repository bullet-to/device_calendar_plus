package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/** `RruleString` owns the RRULE grammar every reader and writer of a rule's parts shares. */
internal class RruleStringTest {
    private fun utc(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int): Long =
        Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(year, month - 1, day, hour, minute, second)
        }.timeInMillis

    @Test
    fun params_stripsThePrefixUppercasesKeysAndTrimsValues() {
        assertEquals(
            mapOf("FREQ" to "WEEKLY", "BYDAY" to "MO,WE", "COUNT" to "3"),
            RruleString.params("RRULE:freq=WEEKLY; byday = MO,WE ;COUNT=3")
        )
    }

    // A trailing `;` leaves an empty part (withUntil relies on it being
    // dropped), and a repeated key resolves to its last value.
    @Test
    fun params_dropsEmptyPartsAndLastRepeatedKeyWins() {
        assertEquals(
            mapOf("FREQ" to "DAILY", "COUNT" to "2"),
            RruleString.params("FREQ=DAILY;;COUNT=1;COUNT=2;")
        )
    }

    // A key must match whole: BYMONTH is not a prefix hit on BYMONTHDAY.
    @Test
    fun params_keysAreWholeParts() {
        val params = RruleString.params("FREQ=MONTHLY;BYMONTHDAY=15")
        assertFalse("BYMONTH" in params)
        assertEquals("15", params["BYMONTHDAY"])
    }

    @Test
    fun withCount_replacesAnyEndAndKeepsTheRestAsWritten() {
        assertEquals(
            "FREQ=WEEKLY;byday=MO;COUNT=2",
            RruleString.withCount("RRULE:FREQ=WEEKLY;count=5;byday=MO", 2)
        )
        assertEquals(
            "FREQ=DAILY;COUNT=2",
            RruleString.withCount("FREQ=DAILY;UNTIL=20261001;;", 2)
        )
        assertEquals("FREQ=DAILY;COUNT=2", RruleString.withCount("FREQ=DAILY", 2))
    }

    // A timed series' UNTIL is a UTC date-time; an all-day series' is the
    // date alone.
    @Test
    fun withUntil_writesAUtcDateTimeOrADateAlone() {
        val until = utc(2026, 10, 1, 21, 59, 59)
        assertEquals(
            "FREQ=WEEKLY;BYDAY=MO;UNTIL=20261001T215959Z",
            RruleString.withUntil("FREQ=WEEKLY;BYDAY=MO;COUNT=5", until, dateOnly = false)
        )
        assertEquals(
            "FREQ=WEEKLY;BYDAY=MO;UNTIL=20261001",
            RruleString.withUntil("FREQ=WEEKLY;BYDAY=MO;COUNT=5", until, dateOnly = true)
        )
    }
}
