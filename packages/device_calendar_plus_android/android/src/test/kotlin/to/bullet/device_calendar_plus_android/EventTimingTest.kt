package to.bullet.device_calendar_plus_android

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * `storedEndMillis` derives a row's end from DTEND, else DTSTART + DURATION:
 * a recurring master stores DURATION with a NULL DTEND (#122).
 *
 * `resolveEditedBounds` decides the DTSTART/DTEND an updateEvent edit writes:
 * a bare all-day toggle takes the row's toggleSpan, anything else stores the
 * provided bounds in the effective frame.
 */
internal class EventTimingTest {
    // "P{n}S" is the form the plugin writes (the timed-master integration
    // test reaches it); other apps and sync adapters write the ISO form,
    // which the integration tests never do.
    @Test
    fun storedEndMillis_parsesEveryDurationForm() {
        assertEquals(1_000L + 3_600_000L, storedEndMillis(1_000L, null, "P3600S"))
        assertEquals(3_600_000L, storedEndMillis(0L, null, "PT1H"))
        assertEquals(86_400_000L, storedEndMillis(0L, null, "P1D"))
        assertEquals(
            ((7 + 2) * 86_400L + 3 * 3_600L + 4 * 60L + 5L) * 1_000L,
            storedEndMillis(0L, null, "P1W2DT3H4M5S"),
        )
        // DTEND wins over DURATION when both are stored.
        assertEquals(2_000L, storedEndMillis(1_000L, 2_000L, "P1D"))
    }

    // The fallthrough buildEventMapFromCursor's `?: rawStart` relies on; no
    // integration test reaches it either.
    @Test
    fun storedEndMillis_unparseableOrAbsentDuration_returnsNull() {
        assertNull(storedEndMillis(0L, null, "garbage"))
        assertNull(storedEndMillis(0L, null, "3600"))
        assertNull(storedEndMillis(0L, null, null))
    }

    private val losAngeles = TimeZone.getTimeZone("America/Los_Angeles")
    private val utc = TimeZone.getTimeZone("UTC")
    private val hour = 3_600_000L

    // 23:30 LA is the next UTC date, so a timed bound left under ALL_DAY=1
    // would read back a day off.
    private val lateEvening = instantAt(losAngeles, 2026, 10, 3, 23, 30)

    // Each case names only what it varies; the row starts at lateEvening and
    // lasts an hour unless a case says otherwise.
    private fun resolve(
        start: Long? = null,
        end: Long? = null,
        newAllDay: Boolean? = null,
        rowAllDay: Boolean = false,
    ) = resolveEditedBounds(
        currentStart = lateEvening,
        durationMillis = hour,
        startMillis = start,
        endMillis = end,
        newAllDay = newAllDay,
        rowAllDay = rowAllDay,
        zone = losAngeles,
    )

    // 23:30-00:30 LA crosses midnight, so the all-day span covers both
    // local dates: Oct 3 through the exclusive end of Oct 4.
    @Test
    fun resolveEditedBounds_bareToggleOfTimedRow_isItsLocalDaysAsUtcDates() {
        assertEquals(
            instantAt(utc, 2026, 10, 3) to instantAt(utc, 2026, 10, 5),
            resolve(newAllDay = true),
        )
    }

    // Already all-day, or not toggling: nothing to move.
    @Test
    fun resolveEditedBounds_noDatesAndNoToggle_leavesBothBounds() {
        val none = null to null
        assertEquals(none, resolve(newAllDay = true, rowAllDay = true))
        assertEquals(none, resolve(newAllDay = false))
        assertEquals(none, resolve())
    }

    // Provided bounds are stored in the effective frame: the patch's flag,
    // else the row's. A missing bound stays null.
    @Test
    fun resolveEditedBounds_providedBounds_storedInEffectiveFrame() {
        val utcDate = instantAt(utc, 2026, 10, 3)
        assertEquals(utcDate to null, resolve(start = lateEvening, newAllDay = true))
        assertEquals(null to utcDate, resolve(end = lateEvening, rowAllDay = true))
        assertEquals(
            lateEvening to lateEvening + hour,
            resolve(
                start = lateEvening,
                end = lateEvening + hour,
                newAllDay = false,
                rowAllDay = true,
            ),
        )
    }
}
