package to.bullet.device_calendar_plus_android

import android.provider.CalendarContract.Attendees

/** A required, invited attendee row with [email], [relationship] and [name]. */
internal fun attendeeRow(email: String?, relationship: Int?, name: String? = null) = AttendeeRow(
    email = email,
    name = name,
    type = Attendees.TYPE_REQUIRED,
    relationship = relationship,
    status = Attendees.ATTENDEE_STATUS_INVITED
)

internal val organizerRow = attendeeRow("owner@example.com", Attendees.RELATIONSHIP_ORGANIZER)
internal val guestRow = attendeeRow("guest@example.com", Attendees.RELATIONSHIP_ATTENDEE)
