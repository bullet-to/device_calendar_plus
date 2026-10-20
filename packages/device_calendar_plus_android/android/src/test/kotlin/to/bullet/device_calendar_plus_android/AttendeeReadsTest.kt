package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class AttendeeReadsTest {
    @Test
    fun organizerOf_readsTheOrganizerRow() {
        val named = organizer.copy(name = "Owner")

        assertEquals(
            mapOf("name" to "Owner", "emailAddress" to "owner@example.com"),
            organizerOf(listOf(guest, named), eventOrganizer = "other@example.com")
        )
    }

    @Test
    fun organizerOf_leavesOutAMissingName() {
        assertEquals(
            mapOf("emailAddress" to "owner@example.com"),
            organizerOf(listOf(organizer, guest), eventOrganizer = null)
        )
    }

    @Test
    fun organizerOf_fallsBackToTheEventsColumnWithoutAnOrganizerRow() {
        assertEquals(
            mapOf("emailAddress" to "fallback@example.com"),
            organizerOf(listOf(guest), eventOrganizer = "fallback@example.com")
        )
    }

    @Test
    fun organizerOf_fallsBackWhenTheOrganizerRowIsBlank() {
        val blank = row(" ", Attendees.RELATIONSHIP_ORGANIZER)

        assertEquals(
            mapOf("emailAddress" to "fallback@example.com"),
            organizerOf(listOf(blank, guest), eventOrganizer = "fallback@example.com")
        )
    }

    @Test
    fun organizerOf_isNullWithoutAttendeeRows() {
        // The provider fills Events.ORGANIZER in on every insert, so the
        // column alone doesn't mean the event has an organizer.
        assertNull(organizerOf(emptyList(), eventOrganizer = "owner@example.com"))
    }

    @Test
    fun organizerOf_isNullWithoutAnOrganizerRowOrColumn() {
        assertNull(organizerOf(listOf(guest), eventOrganizer = null))
        assertNull(organizerOf(listOf(guest), eventOrganizer = ""))
    }

    @Test
    fun organizerOf_namedRowWithoutAnEmail_readsTheNameAlone() {
        // Events.ORGANIZER can name someone else (the calendar's owner
        // account), so it isn't merged in with the row's name.
        val nameOnly = row(" ", Attendees.RELATIONSHIP_ORGANIZER, name = "Owner")

        assertEquals(
            mapOf("name" to "Owner"),
            organizerOf(listOf(nameOnly, guest), eventOrganizer = "fallback@example.com")
        )
        assertEquals(
            mapOf("name" to "Owner"),
            organizerOf(listOf(nameOnly.copy(email = null)), eventOrganizer = "fallback@example.com")
        )
    }
}
