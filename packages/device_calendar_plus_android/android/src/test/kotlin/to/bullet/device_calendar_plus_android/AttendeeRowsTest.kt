package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class AttendeeRowsTest {
    private val unknown = attendeeRow("unknown@example.com", null)
    private val existing = listOf(organizerRow, guestRow, unknown)

    @Test
    fun applyTo_unchanged_keepsEveryRow() {
        assertEquals(existing, RowsPatch.Unchanged.applyTo(existing))
    }

    @Test
    fun applyTo_clear_keepsOnlyTheOrganizer() {
        assertEquals(listOf(organizerRow), RowsPatch.Clear.applyTo(existing))
    }

    @Test
    fun applyTo_set_replacesEveryRowButTheOrganizer() {
        val newGuest = attendeeRow("new@example.com", Attendees.RELATIONSHIP_SPEAKER)

        assertEquals(
            listOf(organizerRow, newGuest),
            RowsPatch.Set(listOf(newGuest)).applyTo(existing)
        )
    }

    @Test
    fun applyTo_setWithAnOrganizer_replacesTheOrganizerToo() {
        val newOrganizer = attendeeRow("chair@example.com", Attendees.RELATIONSHIP_ORGANIZER)

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
}
