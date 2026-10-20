/// Who organized a calendar event (read-only); see `Event.organizer` for
/// where each platform reads it.
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
