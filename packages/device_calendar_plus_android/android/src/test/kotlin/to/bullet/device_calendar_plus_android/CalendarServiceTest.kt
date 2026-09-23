package to.bullet.device_calendar_plus_android

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.provider.CalendarContract
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.invocation.InvocationOnMock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Calendar Provider has no "immutable" flag, so the write guards derive
 * it from CALENDAR_ACCESS_LEVEL, and createCalendar refuses the account types
 * listSources reports as non-creatable. None of that can be set up from an
 * integration test — a third-party app only ever gets owner-level rows out of
 * the provider — so the rows are faked here (#126).
 */
internal class CalendarServiceTest {
    private val resolver: ContentResolver = Mockito.mock(ContentResolver::class.java)
    private val context: Context = Mockito.mock(Context::class.java).also {
        Mockito.`when`(it.contentResolver).thenReturn(resolver)
    }
    private val service = CalendarService(context)

    /** A cursor over [rows], each a column-name → value map. */
    private fun cursorOf(vararg rows: Map<String, Any?>): Cursor {
        val cursor = Mockito.mock(Cursor::class.java)
        val columns = rows.flatMap { it.keys }.distinct()
        var position = -1
        fun cell(inv: InvocationOnMock) = rows[position][columns[inv.getArgument<Int>(0)]]

        Mockito.`when`(cursor.moveToNext()).thenAnswer { ++position < rows.size }
        Mockito.`when`(cursor.moveToFirst()).thenAnswer {
            position = 0
            rows.isNotEmpty()
        }
        Mockito.`when`(cursor.getColumnIndex(anyString()))
            .thenAnswer { columns.indexOf(it.getArgument<String>(0)) }
        Mockito.`when`(cursor.getColumnIndexOrThrow(anyString()))
            .thenAnswer { columns.indexOf(it.getArgument<String>(0)) }
        Mockito.`when`(cursor.isNull(anyInt())).thenAnswer { cell(it) == null }
        Mockito.`when`(cursor.getString(anyInt())).thenAnswer { cell(it) as String? }
        Mockito.`when`(cursor.getInt(anyInt())).thenAnswer { (cell(it) as Int?) ?: 0 }
        return cursor
    }

    private fun providerReturns(cursor: Cursor) {
        Mockito.`when`(resolver.query(any(), any(), any(), any(), any())).thenReturn(cursor)
    }

    private fun accessLevelRow(level: Int) =
        mapOf(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL to level)

    private fun calendarRow(id: String?, name: String?) = mapOf(
        CalendarContract.Calendars._ID to id,
        CalendarContract.Calendars.CALENDAR_DISPLAY_NAME to name,
        CalendarContract.Calendars.CALENDAR_COLOR to null,
        CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL to CalendarContract.Calendars.CAL_ACCESS_OWNER,
        CalendarContract.Calendars.ACCOUNT_NAME to null,
        CalendarContract.Calendars.ACCOUNT_TYPE to null,
        CalendarContract.Calendars.IS_PRIMARY to null,
        CalendarContract.Calendars.VISIBLE to null,
    )

    private fun codeOf(result: Result<*>): String =
        (result.exceptionOrNull() as CalendarException).code

    // --- createCalendar ---

    // listSources marks every non-local account supportsCalendarCreation=false,
    // but createCalendar used to CALLER_IS_SYNCADAPTER-insert under it anyway,
    // leaving a phantom calendar the real sync adapter can wipe.
    @Test
    fun createCalendar_nonLocalAccountType_isReadOnlyAndNeverInserts() {
        val result = service.createCalendar("Work", null, "someone@gmail.com", "com.google")

        assertEquals(PlatformExceptionCodes.READ_ONLY, codeOf(result))
        verify(resolver, never()).insert(any(), any())
    }

    // --- updateCalendar ---

    @Test
    fun updateCalendar_readOnlyCalendar_isReadOnlyAndNeverWrites() {
        providerReturns(cursorOf(accessLevelRow(CalendarContract.Calendars.CAL_ACCESS_READ)))

        val result = service.updateCalendar("7", "Renamed", null)

        assertEquals(PlatformExceptionCodes.READ_ONLY, codeOf(result))
        verify(resolver, never()).update(any(), any(), any(), any())
    }

    // The threshold is the one listCalendars reports as `readOnly`, so a
    // calendar the list calls writable is one updateCalendar accepts.
    @Test
    fun updateCalendar_contributorCalendar_writes() {
        providerReturns(cursorOf(accessLevelRow(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR)))
        Mockito.`when`(resolver.update(any(), any(), any(), any())).thenReturn(1)

        val result = service.updateCalendar("7", "Renamed", null)

        assertTrue(result.isSuccess, "$result")
    }

    // --- deleteCalendar ---

    @Test
    fun deleteCalendar_readOnlyCalendar_isReadOnlyAndNeverDeletes() {
        providerReturns(cursorOf(accessLevelRow(CalendarContract.Calendars.CAL_ACCESS_READ)))

        val result = service.deleteCalendar("7")

        assertEquals(PlatformExceptionCodes.READ_ONLY, codeOf(result))
        verify(resolver, never()).delete(any(), any(), any())
    }

    @Test
    fun deleteCalendar_unknownCalendar_isNotFound() {
        providerReturns(cursorOf())

        val result = service.deleteCalendar("7")

        assertEquals(PlatformExceptionCodes.NOT_FOUND, codeOf(result))
        verify(resolver, never()).delete(any(), any(), any())
    }

    // --- listCalendars ---

    // Dart casts `name` with `as String`, so a provider row with a NULL
    // display name used to crash listCalendars for every calendar.
    @Test
    fun listCalendars_nullDisplayName_readsAsEmptyString() {
        providerReturns(cursorOf(calendarRow(id = "3", name = null)))

        val calendars = service.listCalendars().getOrThrow()

        assertEquals("", calendars.single()["name"])
    }

    @Test
    fun listCalendars_nullId_skipsTheRow() {
        providerReturns(
            cursorOf(calendarRow(id = null, name = "Ghost"), calendarRow(id = "4", name = "Real"))
        )

        val calendars = service.listCalendars().getOrThrow()

        assertEquals(listOf("4"), calendars.map { it["id"] })
    }
}
