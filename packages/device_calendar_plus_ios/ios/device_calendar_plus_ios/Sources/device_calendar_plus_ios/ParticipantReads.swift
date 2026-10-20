import EventKit

// EKParticipants read out to the shared, read-only model: `Event.attendees`
// and `Event.organizer`. Android's counterpart is `AttendeeReads.kt`.

/// [participants] as shared `Attendee` maps, the organizer (`.chair`) left
/// out. Names and emails pass through as EventKit gives them, blank or not;
/// only [organizerMap] drops blank values.
func attendeeMaps(_ participants: [EKParticipant]) -> [[String: Any]] {
  participants.compactMap { participant in
    // Skip the organizer
    if participant.participantRole == .chair {
      return nil
    }

    var attendeeMap: [String: Any] = [
      "role": participantRoleToString(participant.participantRole),
      "status": participantStatusToString(participant.participantStatus),
    ]
    if let name = participant.name {
      attendeeMap["name"] = name
    }
    if let email = participantEmail(participant) {
      attendeeMap["emailAddress"] = email
    }
    return attendeeMap
  }
}

/// [organizer] as the shared `Organizer` map; see `organizerMap(name:url:)`.
func organizerMap(_ organizer: EKParticipant) -> [String: String]? {
  organizerMap(name: organizer.name, url: organizer.url)
}

/// The shared `Organizer` map for a participant's [name] and [url], or nil
/// when it has neither a name nor an email. Unlike attendees, a blank (empty
/// or whitespace-only) value is left out, matching Android's organizerOf.
/// Takes the participant's fields rather than an EKParticipant, which has no
/// public initializer, so tests can drive it.
func organizerMap(name: String?, url: URL) -> [String: String]? {
  var map: [String: String] = [:]
  if let name = nonBlank(name) {
    map["name"] = name
  }
  if let email = nonBlank(mailtoEmail(url)) {
    map["emailAddress"] = email
  }
  return map.isEmpty ? nil : map
}

/// The participant's email, embedded in its URL as `mailto:`; nil when the
/// URL isn't a `mailto:` one.
private func participantEmail(_ participant: EKParticipant) -> String? {
  mailtoEmail(participant.url)
}

/// The email embedded in [url] as `mailto:`; nil when it isn't a `mailto:`
/// URL.
private func mailtoEmail(_ url: URL) -> String? {
  let urlString = url.absoluteString
  return urlString.hasPrefix("mailto:") ? String(urlString.dropFirst(7)) : nil
}

/// [value], or nil when it is nil, empty or whitespace-only (as Kotlin's
/// isBlank has it).
private func nonBlank(_ value: String?) -> String? {
  guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return nil
  }
  return value
}

private func participantRoleToString(_ role: EKParticipantRole) -> String {
  switch role {
  case .required: return "required"
  case .optional: return "optional"
  case .chair: return "chair"
  case .nonParticipant: return "nonParticipant"
  case .unknown: return "required"
  @unknown default: return "required"
  }
}

private func participantStatusToString(_ status: EKParticipantStatus) -> String {
  switch status {
  case .accepted: return "accepted"
  case .declined: return "declined"
  case .tentative: return "tentative"
  case .pending: return "pending"
  case .delegated: return "delegated"
  case .completed: return "completed"
  case .inProcess: return "inProcess"
  case .unknown: return "none"
  @unknown default: return "none"
  }
}
