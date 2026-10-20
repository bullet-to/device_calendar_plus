package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class AttendeeReadsTest {
    @Test
    fun organizerOf_readsTheOrganizerRow() {
        val named = organizerRow.copy(name = "Owner")

        assertEquals(
            mapOf("name" to "Owner", "emailAddress" to "owner@example.com"),
            organizerOf(listOf(guestRow, named), eventOrganizer = "other@example.com")
        )
    }

    @Test
    fun organizerOf_leavesOutAMissingName() {
        assertEquals(
            mapOf("emailAddress" to "owner@example.com"),
            organizerOf(listOf(organizerRow, guestRow), eventOrganizer = null)
        )
    }

    @Test
    fun organizerOf_fallsBackToTheEventsColumnWithoutAnOrganizerRow() {
        assertEquals(
            mapOf("emailAddress" to "fallback@example.com"),
            organizerOf(listOf(guestRow), eventOrganizer = "fallback@example.com")
        )
    }

    @Test
    fun organizerOf_fallsBackWhenTheOrganizerRowIsBlank() {
        val blank = attendeeRow(" ", Attendees.RELATIONSHIP_ORGANIZER)

        assertEquals(
            mapOf("emailAddress" to "fallback@example.com"),
            organizerOf(listOf(blank, guestRow), eventOrganizer = "fallback@example.com")
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
        assertNull(organizerOf(listOf(guestRow), eventOrganizer = null))
        assertNull(organizerOf(listOf(guestRow), eventOrganizer = ""))
    }

    @Test
    fun organizerOf_namedRowWithoutAnEmail_readsTheNameAlone() {
        // Events.ORGANIZER can name someone else (the calendar's owner
        // account), so it isn't merged in with the row's name.
        val nameOnly = attendeeRow(" ", Attendees.RELATIONSHIP_ORGANIZER, name = "Owner")

        assertEquals(
            mapOf("name" to "Owner"),
            organizerOf(listOf(nameOnly, guestRow), eventOrganizer = "fallback@example.com")
        )
        assertEquals(
            mapOf("name" to "Owner"),
            organizerOf(listOf(nameOnly.copy(email = null)), eventOrganizer = "fallback@example.com")
        )
    }
}
