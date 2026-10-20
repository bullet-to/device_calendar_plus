package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

internal class AttendeeRowsTest {
    private fun row(email: String, relationship: Int?) = AttendeeRow(
        email = email,
        name = null,
        type = Attendees.TYPE_REQUIRED,
        relationship = relationship,
        status = Attendees.ATTENDEE_STATUS_INVITED
    )

    private val organizer = row("owner@example.com", Attendees.RELATIONSHIP_ORGANIZER)
    private val guest = row("guest@example.com", Attendees.RELATIONSHIP_ATTENDEE)
    private val unknown = row("unknown@example.com", null)
    private val existing = listOf(organizer, guest, unknown)

    @Test
    fun applyTo_unchanged_keepsEveryRow() {
        assertEquals(existing, RowsPatch.Unchanged.applyTo(existing))
    }

    @Test
    fun applyTo_clear_keepsOnlyTheOrganizer() {
        assertEquals(listOf(organizer), RowsPatch.Clear.applyTo(existing))
    }

    @Test
    fun applyTo_set_replacesEveryRowButTheOrganizer() {
        val newGuest = row("new@example.com", Attendees.RELATIONSHIP_SPEAKER)

        assertEquals(
            listOf(organizer, newGuest),
            RowsPatch.Set(listOf(newGuest)).applyTo(existing)
        )
    }

    @Test
    fun applyTo_setWithAnOrganizer_replacesTheOrganizerToo() {
        val newOrganizer = row("chair@example.com", Attendees.RELATIONSHIP_ORGANIZER)

        assertEquals(
            listOf(newOrganizer),
            RowsPatch.Set(listOf(newOrganizer)).applyTo(existing)
        )
    }

    @Test
    fun attendeeTypeFromName_mapsEveryName() {
        assertEquals(Attendees.TYPE_NONE, attendeeTypeFromName("none"))
        assertEquals(Attendees.TYPE_REQUIRED, attendeeTypeFromName("required"))
        assertEquals(Attendees.TYPE_OPTIONAL, attendeeTypeFromName("optional"))
        assertEquals(Attendees.TYPE_RESOURCE, attendeeTypeFromName("resource"))
    }

    @Test
    fun attendeeTypeFromName_throwsOnAnUnknownName() {
        assertFailsWith<IllegalArgumentException> { attendeeTypeFromName("chair") }
    }

    @Test
    fun attendeeRelationshipFromName_mapsEveryName() {
        assertEquals(Attendees.RELATIONSHIP_NONE, attendeeRelationshipFromName("none"))
        assertEquals(Attendees.RELATIONSHIP_ATTENDEE, attendeeRelationshipFromName("attendee"))
        assertEquals(Attendees.RELATIONSHIP_ORGANIZER, attendeeRelationshipFromName("organizer"))
        assertEquals(Attendees.RELATIONSHIP_PERFORMER, attendeeRelationshipFromName("performer"))
        assertEquals(Attendees.RELATIONSHIP_SPEAKER, attendeeRelationshipFromName("speaker"))
    }

    @Test
    fun attendeeRelationshipFromName_throwsOnAnUnknownName() {
        assertFailsWith<IllegalArgumentException> { attendeeRelationshipFromName("host") }
    }

    @Test
    fun attendeeStatusFromName_mapsEveryName() {
        assertEquals(Attendees.ATTENDEE_STATUS_NONE, attendeeStatusFromName("none"))
        assertEquals(Attendees.ATTENDEE_STATUS_ACCEPTED, attendeeStatusFromName("accepted"))
        assertEquals(Attendees.ATTENDEE_STATUS_DECLINED, attendeeStatusFromName("declined"))
        assertEquals(Attendees.ATTENDEE_STATUS_INVITED, attendeeStatusFromName("invited"))
        assertEquals(Attendees.ATTENDEE_STATUS_TENTATIVE, attendeeStatusFromName("tentative"))
    }

    @Test
    fun attendeeStatusFromName_throwsOnAnUnknownName() {
        assertFailsWith<IllegalArgumentException> { attendeeStatusFromName("maybe") }
    }

    @Test
    fun attendeeRowFromArg_mapsAndroidNamesToProviderConstants() {
        val parsed = attendeeRowFromArg(
            mapOf(
                "email" to "ada@example.com",
                "name" to "Ada",
                "type" to "resource",
                "relationship" to "performer",
                "status" to "tentative"
            )
        )

        assertEquals(
            AttendeeRow(
                email = "ada@example.com",
                name = "Ada",
                type = Attendees.TYPE_RESOURCE,
                relationship = Attendees.RELATIONSHIP_PERFORMER,
                status = Attendees.ATTENDEE_STATUS_TENTATIVE
            ),
            parsed
        )
    }

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
            organizerOf(existing, eventOrganizer = null)
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
        val blank = AttendeeRow(
            email = " ",
            name = null,
            type = null,
            relationship = Attendees.RELATIONSHIP_ORGANIZER,
            status = null
        )

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
}
