/// The organizer of a calendar event (read-only).
///
/// Read from `EKEvent.organizer` on iOS, and on Android from the event's
/// `RELATIONSHIP_ORGANIZER` attendee row, falling back to
/// `CalendarContract.Events.ORGANIZER` (an email only, so [name] is null)
/// when there is no such row. The organizer is never listed in
/// `Event.attendees`. See `Event.organizer` for when there is none.
class Organizer {
  /// Display name of the organizer, when the platform has one.
  final String? name;

  /// Email address of the organizer, when the platform has one.
  final String? emailAddress;

  const Organizer({this.name, this.emailAddress});

  factory Organizer.fromMap(Map<String, dynamic> map) {
    return Organizer(
      name: map['name'] as String?,
      emailAddress: map['emailAddress'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (name != null) 'name': name,
      if (emailAddress != null) 'emailAddress': emailAddress,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Organizer &&
        other.name == name &&
        other.emailAddress == emailAddress;
  }

  @override
  int get hashCode => Object.hash(name, emailAddress);

  @override
  String toString() => 'Organizer(name: $name, email: $emailAddress)';
}
