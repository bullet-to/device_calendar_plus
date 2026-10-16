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
 * each provided bound is stored in the effective frame, and a toggle in
 * either direction fills a bound it leaves out from the row's span in the
 * new frame (toggleSpan to all-day, timedSpan to timed). Without a toggle a
 * missing bound stays null.
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
    // else the row's. A missing bound stays null unless the edit toggles.
    private val lateEveningUtcDate = instantAt(utc, 2026, 10, 3)

    // A toggle with one date takes the other bound from the row's
    // toggleSpan, as EventKit floats it onto its local date (#204): left
    // timed under ALL_DAY=1 it read back as its UTC date.
    @Test
    fun resolveEditedBounds_toggleToAllDayWithStartOnly_endIsTheRowsLastLocalDay() {
        assertEquals(
            instantAt(utc, 2026, 10, 1) to instantAt(utc, 2026, 10, 5),
            resolve(start = instantAt(losAngeles, 2026, 10, 1), newAllDay = true),
        )
    }

    @Test
    fun resolveEditedBounds_toggleToAllDayWithEndOnly_startIsTheRowsLocalDate() {
        assertEquals(
            lateEveningUtcDate to instantAt(utc, 2026, 10, 8),
            resolve(end = instantAt(losAngeles, 2026, 10, 8), newAllDay = true),
        )
    }

    // An all-day row: 3 to 5 October, stored as the UTC midnights of 3 and
    // (exclusive) 5 October.
    private fun resolveAllDayRow(start: Long? = null, end: Long? = null) =
        resolveEditedBounds(
            currentStart = lateEveningUtcDate,
            durationMillis = 2 * AllDayDates.MILLIS_PER_DAY,
            startMillis = start,
            endMillis = end,
            newAllDay = false,
            rowAllDay = true,
            zone = losAngeles,
        )

    // The reverse toggle alone keeps the row's days, from the first one's
    // local midnight to the last second of the last, the timed reading
    // EventKit gives the all-day dates it holds (#205, #216). Left as UTC
    // midnights under ALL_DAY=0, they read back as the evening before west
    // of UTC.
    @Test
    fun resolveEditedBounds_bareToggleOfAllDayRow_isItsDaysInTheLocalZone() {
        assertEquals(
            instantAt(losAngeles, 2026, 10, 3) to instantAt(losAngeles, 2026, 10, 5) - 1_000L,
            resolveAllDayRow(),
        )
    }

    @Test
    fun resolveEditedBounds_toggleToTimedWithStartOnly_endIsTheRowsLastLocalSecond() {
        val nineAm = instantAt(losAngeles, 2026, 10, 3, 9)
        assertEquals(
            nineAm to instantAt(losAngeles, 2026, 10, 5) - 1_000L,
            resolveAllDayRow(start = nineAm),
        )
    }

    @Test
    fun resolveEditedBounds_providedEnd_rowAllDayFallback_storedAsUtcDate() {
        assertEquals(null to lateEveningUtcDate, resolve(end = lateEvening, rowAllDay = true))
    }

    @Test
    fun resolveEditedBounds_patchFalseOverRowAllDay_storedTimed() {
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
