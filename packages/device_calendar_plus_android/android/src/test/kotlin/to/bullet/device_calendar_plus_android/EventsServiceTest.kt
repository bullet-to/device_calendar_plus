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

    private val sydney = TimeZone.getTimeZone("Australia/Sydney")
    private val utc = TimeZone.getTimeZone("UTC")

    private fun at(zone: TimeZone, year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, hour, minute, 0)
        }.timeInMillis

    // The helper reads the device zone through Calendar.getInstance(), so pin
    // it for the assertion and put it back afterwards.
    private fun <T> inZone(zone: TimeZone, block: () -> T): T {
        val previous = TimeZone.getDefault()
        TimeZone.setDefault(zone)
        try {
            return block()
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    // A window ending on a local midnight already names the day boundary:
    // listEvents(day, day + 1) must keep excluding the all-day event on
    // day + 1, so the edge stays at that date's UTC midnight.
    @Test
    fun allDayWindowEndUtcMidnight_endOnLocalMidnight_isThatDatesUtcMidnight() {
        val end = inZone(sydney) { service.allDayWindowEndUtcMidnight(at(sydney, 2026, 9, 26)) }
        assertEquals(at(utc, 2026, 9, 26), end)
    }

    // A window ending inside a date has to cover that whole date, or a
    // same-day window (10:00–11:00) collapses to an empty all-day range and
    // drops the day's all-day event, which iOS includes.
    @Test
    fun allDayWindowEndUtcMidnight_endInsideDate_roundsUpToNextUtcMidnight() {
        val end = inZone(sydney) { service.allDayWindowEndUtcMidnight(at(sydney, 2026, 9, 26, 11)) }
        assertEquals(at(utc, 2026, 9, 27), end)
    }

    // The first instant past midnight is inside the new date, not on its
    // boundary, so it rounds up like any other in-date end.
    @Test
    fun allDayWindowEndUtcMidnight_endJustAfterLocalMidnight_roundsUp() {
        val end = inZone(sydney) { service.allDayWindowEndUtcMidnight(at(sydney, 2026, 9, 26) + 1) }
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
