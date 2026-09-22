package to.bullet.device_calendar_plus_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/** `RruleString` owns the RRULE grammar every reader and writer of a rule's parts shares. */
internal class RruleStringTest {
    @Test
    fun params_stripsThePrefixUppercasesKeysAndTrimsValues() {
        assertEquals(
            mapOf("FREQ" to "WEEKLY", "BYDAY" to "MO,WE", "COUNT" to "3"),
            RruleString.params("RRULE:freq=WEEKLY; byday = MO,WE ;COUNT=3")
        )
    }

    @Test
    fun params_dropsEmptyAndKeylessParts() {
        assertEquals(
            mapOf("FREQ" to "DAILY", "BYMONTH" to ""),
            RruleString.params("FREQ=DAILY;;BYMONTH=;=5;garbage")
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
    fun withEnd_replacesCountOrUntilAndKeepsTheRestAsWritten() {
        assertEquals(
            "FREQ=WEEKLY;byday=MO;UNTIL=20261001T215959Z",
            RruleString.withEnd("RRULE:FREQ=WEEKLY;count=5;byday=MO", "UNTIL=20261001T215959Z")
        )
        assertEquals(
            "FREQ=DAILY;COUNT=2",
            RruleString.withEnd("FREQ=DAILY;UNTIL=20261001;;", "COUNT=2")
        )
        assertEquals("FREQ=DAILY;COUNT=2", RruleString.withEnd("FREQ=DAILY", "COUNT=2"))
    }
}
