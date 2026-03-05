/// Represents a calendar source/account on the device.
///
/// Calendar sources are containers that group calendars together.
/// On iOS, these correspond to `EKSource` (iCloud, local, subscribed, etc.).
/// On Android, these correspond to account name + account type combinations
/// from the Calendar Provider.
///
/// Use [DeviceCalendar.listSources] to retrieve available sources, then pass
/// the source information to platform-specific options when creating calendars.
class CalendarSource {
  /// Unique identifier for the source.
  ///
  /// On iOS, this is the `EKSource.sourceIdentifier`.
  /// On Android, this is a composite key of `accountName:accountType`.
  final String id;

  /// User-facing title of the source.
  ///
  /// Examples: "iCloud", "user@gmail.com", "Local"
  final String title;

  /// The type of the source.
  ///
  /// Common values:
  /// - iOS: "local", "caldav", "exchange", "subscribed", "birthdays"
  /// - Android: "com.google", "com.microsoft.exchange", "LOCAL"
  final String type;

  /// Whether calendars can be created in this source.
  ///
  /// Some sources (like subscribed calendars or birthdays) don't allow
  /// creating new calendars.
  final bool allowsCalendarCreation;

  /// Creates an immutable calendar source description.
  const CalendarSource({
    required this.id,
    required this.title,
    required this.type,
    required this.allowsCalendarCreation,
  });

  /// Builds a calendar source object from a platform channel payload.
  factory CalendarSource.fromMap(Map<String, dynamic> map) {
    return CalendarSource(
      id: map['id'] as String,
      title: map['title'] as String,
      type: map['type'] as String,
      allowsCalendarCreation: map['allowsCalendarCreation'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CalendarSource &&
        other.id == id &&
        other.title == title &&
        other.type == type &&
        other.allowsCalendarCreation == allowsCalendarCreation;
  }

  @override
  int get hashCode {
    return Object.hash(id, title, type, allowsCalendarCreation);
  }

  @override
  String toString() {
    return 'CalendarSource(id: $id, title: $title, type: $type, '
        'allowsCalendarCreation: $allowsCalendarCreation)';
  }
}
