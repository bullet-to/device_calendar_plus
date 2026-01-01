/// Role of an attendee in a calendar event.
///
/// Maps to:
/// - iOS: EKParticipantRole
/// - Android: CalendarContract.Attendees.ATTENDEE_TYPE + ATTENDEE_RELATIONSHIP
enum AttendeeRole {
  /// Unknown or no role specified.
  none,

  /// Required attendee - their attendance is mandatory.
  required,

  /// Optional attendee - their attendance is optional.
  optional,

  /// Resource attendee (e.g., conference room, projector).
  resource,
}

/// Attendance status of an attendee.
///
/// Maps to:
/// - iOS: EKParticipantStatus
/// - Android: CalendarContract.Attendees.ATTENDEE_STATUS
enum AttendeeStatus {
  /// No status or unknown.
  none,

  /// Attendee has been invited but hasn't responded.
  invited,

  /// Attendee accepted the invitation.
  accepted,

  /// Attendee declined the invitation.
  declined,

  /// Attendee tentatively accepted.
  tentative,
}

/// Represents an attendee/invitee of a calendar event.
///
/// This class is used both when creating events with attendees and when
/// reading attendees from existing events.
///
/// Example:
/// ```dart
/// final attendee = Attendee(
///   emailAddress: 'colleague@example.com',
///   name: 'John Doe',
///   role: AttendeeRole.required,
/// );
/// ```
class Attendee {
  /// Display name of the attendee.
  ///
  /// May be null if only email is available.
  final String? name;

  /// Email address of the attendee.
  ///
  /// Required for adding new attendees to an event.
  final String emailAddress;

  /// Role of the attendee (required, optional, resource).
  ///
  /// Defaults to [AttendeeRole.required].
  final AttendeeRole role;

  /// Current attendance status.
  ///
  /// This is typically read-only from the native calendar and represents
  /// the attendee's response to the invitation.
  final AttendeeStatus status;

  /// Whether this attendee is the event organizer.
  ///
  /// Read-only, set by the native calendar.
  final bool isOrganizer;

  /// Whether this attendee is the current device user.
  ///
  /// Read-only, set by the native calendar (iOS only, always false on Android).
  final bool isCurrentUser;

  /// Creates a new attendee.
  ///
  /// [emailAddress] is required. Other fields are optional with sensible defaults.
  Attendee({
    this.name,
    required this.emailAddress,
    this.role = AttendeeRole.required,
    this.status = AttendeeStatus.none,
    this.isOrganizer = false,
    this.isCurrentUser = false,
  });

  /// Creates an Attendee from a map returned by the platform.
  factory Attendee.fromMap(Map<String, dynamic> map) {
    return Attendee(
      name: map['name'] as String?,
      emailAddress: map['emailAddress'] as String,
      role: _parseRole(map['role'] as String?),
      status: _parseStatus(map['status'] as String?),
      isOrganizer: map['isOrganizer'] as bool? ?? false,
      isCurrentUser: map['isCurrentUser'] as bool? ?? false,
    );
  }

  /// Converts this Attendee to a map for platform communication.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'emailAddress': emailAddress,
      'role': role.name,
      'status': status.name,
      'isOrganizer': isOrganizer,
      'isCurrentUser': isCurrentUser,
    };
  }

  static AttendeeRole _parseRole(String? role) {
    if (role == null) return AttendeeRole.none;
    return AttendeeRole.values.firstWhere(
      (r) => r.name == role,
      orElse: () => AttendeeRole.none,
    );
  }

  static AttendeeStatus _parseStatus(String? status) {
    if (status == null) return AttendeeStatus.none;
    return AttendeeStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => AttendeeStatus.none,
    );
  }

  @override
  String toString() {
    return 'Attendee(name: $name, email: $emailAddress, role: $role, '
        'status: $status, isOrganizer: $isOrganizer)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attendee &&
        other.name == name &&
        other.emailAddress == emailAddress &&
        other.role == role &&
        other.status == status &&
        other.isOrganizer == isOrganizer &&
        other.isCurrentUser == isCurrentUser;
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      emailAddress,
      role,
      status,
      isOrganizer,
      isCurrentUser,
    );
  }
}
