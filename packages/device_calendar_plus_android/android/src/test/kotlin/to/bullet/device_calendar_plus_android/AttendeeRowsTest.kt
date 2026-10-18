package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees
import kotlin.test.Test
import kotlin.test.assertEquals

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
        assertEquals(existing, AttendeesPatch.Unchanged.applyTo(existing))
    }

    @Test
    fun applyTo_clear_keepsOnlyTheOrganizer() {
        assertEquals(listOf(organizer), AttendeesPatch.Clear.applyTo(existing))
    }

    @Test
    fun applyTo_set_replacesEveryRowButTheOrganizer() {
        val newGuest = row("new@example.com", Attendees.RELATIONSHIP_SPEAKER)

        assertEquals(
            listOf(organizer, newGuest),
            AttendeesPatch.Set(listOf(newGuest)).applyTo(existing)
        )
    }

    @Test
    fun applyTo_setWithAnOrganizer_replacesTheOrganizerToo() {
        val newOrganizer = row("chair@example.com", Attendees.RELATIONSHIP_ORGANIZER)

        assertEquals(
            listOf(newOrganizer),
            AttendeesPatch.Set(listOf(newOrganizer)).applyTo(existing)
        )
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
