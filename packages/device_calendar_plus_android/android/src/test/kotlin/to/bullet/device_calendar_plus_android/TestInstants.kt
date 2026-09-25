package to.bullet.device_calendar_plus_android

import java.util.Calendar
import java.util.TimeZone

/**
 * Epoch millis of a wall-clock time in [zone], for tests that need a fixed
 * instant without caring about the host's default zone. [month] is 1-based.
 */
internal fun instantAt(
    zone: TimeZone,
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
): Long =
    Calendar.getInstance(zone).apply {
        clear()
        set(year, month - 1, day, hour, minute, 0)
    }.timeInMillis
