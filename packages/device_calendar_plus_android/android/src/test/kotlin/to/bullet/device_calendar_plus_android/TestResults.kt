package to.bullet.device_calendar_plus_android

import kotlin.test.assertEquals
import kotlin.test.assertIs

/** The [CalendarException] code a refused result carries; fails the test if it succeeded. */
internal fun <T> Result<T>.failureCode(): String =
    assertIs<CalendarException>(
        exceptionOrNull(),
        "expected a refusal, got ${getOrNull()}"
    ).code

/** Asserts the result is an INVALID_ARGUMENTS refusal, as Swift's `assertRefused` does. */
internal fun Result<*>.assertRefused() =
    assertEquals(PlatformExceptionCodes.INVALID_ARGUMENTS, failureCode())
