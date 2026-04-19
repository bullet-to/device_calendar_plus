/// Role of an attendee in a calendar event.
enum AttendeeRole {
  /// Attendance is required.
  ///
  /// Available on: Android, iOS
  required,

  /// Attendance is optional.
  ///
  /// Available on: Android, iOS
  optional,

  /// Attendee is the chair/organizer of the event.
  ///
  /// Available on: Android, iOS
  chair,

  /// Attendee is a non-participant (e.g. room resource, FYI).
  ///
  /// Available on: Android, iOS
  nonParticipant;

  /// Safely parses a string to an AttendeeRole enum.
  /// Returns [required] if the value doesn't match any known case.
  static AttendeeRole fromName(String name) {
    return AttendeeRole.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AttendeeRole.required,
    );
  }
}

/// RSVP status of an attendee.
enum AttendeeStatus {
  /// Attendee has accepted the invitation.
  ///
  /// Available on: Android, iOS
  accepted,

  /// Attendee has declined the invitation.
  ///
  /// Available on: Android, iOS
  declined,

  /// Attendee has tentatively accepted.
  ///
  /// Available on: Android, iOS
  tentative,

  /// Invitation is pending (no response yet).
  ///
  /// Available on: Android, iOS
  pending,

  /// Attendee has delegated attendance to another person.
  ///
  /// Available on: iOS only
  delegated,

  /// Attendee has completed (for to-do style events).
  ///
  /// Available on: iOS only
  completed,

  /// Attendee is in process (for to-do style events).
  ///
  /// Available on: iOS only
  inProcess,

  /// Status is unknown or not set.
  ///
  /// Available on: Android, iOS
  none;

  /// Safely parses a string to an AttendeeStatus enum.
  /// Returns [none] if the value doesn't match any known case.
  static AttendeeStatus fromName(String name) {
    return AttendeeStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AttendeeStatus.none,
    );
  }
}

/// A participant in a calendar event (read-only).
///
/// Attendees are populated when fetching events. Neither platform supports
/// programmatic attendee creation through this plugin — use
/// [DeviceCalendar.showCreateEventModal] to let users add attendees via
/// the native UI.
class Attendee {
  /// Display name of the attendee.
  final String? name;

  /// Email address of the attendee.
  final String? emailAddress;

  /// Role in the event (required, optional, chair, etc.).
  final AttendeeRole role;

  /// RSVP status (accepted, declined, tentative, etc.).
  final AttendeeStatus status;

  const Attendee({
    this.name,
    this.emailAddress,
    required this.role,
    required this.status,
  });

  factory Attendee.fromMap(Map<String, dynamic> map) {
    return Attendee(
      name: map['name'] as String?,
      emailAddress: map['emailAddress'] as String?,
      role: AttendeeRole.fromName(map['role'] as String? ?? 'required'),
      status: AttendeeStatus.fromName(map['status'] as String? ?? 'none'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (name != null) 'name': name,
      if (emailAddress != null) 'emailAddress': emailAddress,
      'role': role.name,
      'status': status.name,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attendee &&
        other.name == name &&
        other.emailAddress == emailAddress &&
        other.role == role &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(name, emailAddress, role, status);

  @override
  String toString() =>
      'Attendee(name: $name, email: $emailAddress, role: $role, status: $status)';
}
