package to.bullet.device_calendar_plus_android

import android.content.Context
import java.util.Calendar
import java.util.TimeZone
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

internal class EventsServiceTest {
    private val service = EventsService(
        Mockito.mock(Context::class.java),
        Mockito.mock(CalendarService::class.java),
    )

    // One zone each side of UTC: Sydney's local midnight lands on the previous
    // UTC date, Los Angeles's on the same UTC date, so a rounding slip shows
    // up in one hemisphere even if it cancels out in the other.
    private val sydney = TimeZone.getTimeZone("Australia/Sydney")
    private val losAngeles = TimeZone.getTimeZone("America/Los_Angeles")
    private val utc = TimeZone.getTimeZone("UTC")

    private fun at(zone: TimeZone, year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, hour, minute, 0)
        }.timeInMillis

    // End on a local midnight keeps the boundary (exclusive end).
    @Test
    fun allDayWindowEndUtcMidnight_endOnLocalMidnight_isThatDatesUtcMidnight() {
        val end = service.allDayWindowEndUtcMidnight(at(sydney, 2026, 9, 26), sydney)
        assertEquals(at(utc, 2026, 9, 26), end)
    }

    // End inside a date covers that date.
    @Test
    fun allDayWindowEndUtcMidnight_endInsideDate_roundsUpToNextUtcMidnight() {
        val end = service.allDayWindowEndUtcMidnight(at(sydney, 2026, 9, 26, 11), sydney)
        assertEquals(at(utc, 2026, 9, 27), end)
    }

    // The first instant past midnight is inside the new date, so it covers it.
    @Test
    fun allDayWindowEndUtcMidnight_endJustAfterLocalMidnight_roundsUp() {
        val end = service.allDayWindowEndUtcMidnight(at(sydney, 2026, 9, 26) + 1, sydney)
        assertEquals(at(utc, 2026, 9, 27), end)
    }

    @Test
    fun allDayWindowEndUtcMidnight_endOnLocalMidnight_westOfUtc_isThatDatesUtcMidnight() {
        val end = service.allDayWindowEndUtcMidnight(at(losAngeles, 2026, 9, 26), losAngeles)
        assertEquals(at(utc, 2026, 9, 26), end)
    }

    @Test
    fun allDayWindowEndUtcMidnight_endInsideDate_westOfUtc_roundsUpToNextUtcMidnight() {
        val end = service.allDayWindowEndUtcMidnight(at(losAngeles, 2026, 9, 26, 11), losAngeles)
        assertEquals(at(utc, 2026, 9, 27), end)
    }

    // Regression: a NULL STATUS column used to be read as 0, which is
    // STATUS_TENTATIVE on Android — events with no status came back as
    // "tentative" instead of "none".
    @Test
    fun statusToString_null_returnsNone() {
        assertEquals("none", service.statusToString(null))
    }

    @Test
    fun statusToString_mapsProviderConstants() {
        assertEquals("tentative", service.statusToString(0))
        assertEquals("confirmed", service.statusToString(1))
        assertEquals("canceled", service.statusToString(2))
    }

    // A NULL AVAILABILITY column falls through to the documented default.
    @Test
    fun availabilityToString_null_returnsBusy() {
        assertEquals("busy", service.availabilityToString(null))
    }

    @Test
    fun availabilityToString_mapsProviderConstants() {
        assertEquals("busy", service.availabilityToString(0))
        assertEquals("free", service.availabilityToString(1))
        assertEquals("tentative", service.availabilityToString(2))
    }
}
