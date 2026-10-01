package to.bullet.device_calendar_plus_android

import kotlin.test.assertIs

/** The [CalendarException] code a refused result carries; fails the test if it succeeded. */
internal fun <T> Result<T>.failureCode(): String =
    assertIs<CalendarException>(
        exceptionOrNull(),
        "expected a refusal, got ${getOrNull()}"
    ).code
