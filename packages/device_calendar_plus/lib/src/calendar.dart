/// Cross-platform calendar shape for UI + storage.
/// Keep this lean; event-level fields (like time zone) live on events, not calendars.
class Calendar {
  /// Stable identifier (persist me).
  final String id;

  /// User-visible name ("Work", "Personal", etc.).
  final String name;

  /// Hex like "#RRGGBB" (no alpha). Null if platform didn't supply one.
  final String? colorHex;

  /// True if you shouldn't offer edits on this calendar (read-only/subscribed/etc.).
  final bool readOnly;

  /// Account label/email (iCloud/Google/etc.).
  final String? accountName;

  /// Platform account/source type (e.g., "com.google", "CalDAV", "local").
  final String? accountType;

  /// True for the user's primary/default calendar on that account/device.
  /// - Android: `Calendars.IS_PRIMARY`
  /// - iOS: `eventStore.defaultCalendarForNewEvents` match
  final bool isPrimary;

  /// True if calendar is hidden in OS UI (Android only).
  /// iOS doesn't expose this; we set false by default there.
  final bool hidden;

  const Calendar({
    required this.id,
    required this.name,
    this.colorHex,
    required this.readOnly,
    this.accountName,
    this.accountType,
    this.isPrimary = false,
    this.hidden = false,
  });

  /// Creates a DeviceCalendar from a platform map.
  factory Calendar.fromMap(Map<String, dynamic> map) {
    return Calendar(
      id: map['id'] as String,
      name: map['name'] as String,
      colorHex: map['colorHex'] as String?,
      readOnly: map['readOnly'] as bool? ?? false,
      accountName: map['accountName'] as String?,
      accountType: map['accountType'] as String?,
      isPrimary: map['isPrimary'] as bool? ?? false,
      hidden: map['hidden'] as bool? ?? false,
    );
  }

  /// Converts this DeviceCalendar to a platform map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'colorHex': colorHex,
      'readOnly': readOnly,
      'accountName': accountName,
      'accountType': accountType,
      'isPrimary': isPrimary,
      'hidden': hidden,
    };
  }

  Calendar copyWith({
    String? id,
    String? name,
    String? colorHex,
    bool? readOnly,
    String? accountName,
    String? accountType,
    bool? isPrimary,
    bool? hidden,
  }) {
    return Calendar(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      readOnly: readOnly ?? this.readOnly,
      accountName: accountName ?? this.accountName,
      accountType: accountType ?? this.accountType,
      isPrimary: isPrimary ?? this.isPrimary,
      hidden: hidden ?? this.hidden,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Calendar &&
        other.id == id &&
        other.name == name &&
        other.colorHex == colorHex &&
        other.readOnly == readOnly &&
        other.accountName == accountName &&
        other.accountType == accountType &&
        other.isPrimary == isPrimary &&
        other.hidden == hidden;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      colorHex,
      readOnly,
      accountName,
      accountType,
      isPrimary,
      hidden,
    );
  }

  @override
  String toString() {
    return 'DeviceCalendar(id: $id, name: $name, colorHex: $colorHex, '
        'readOnly: $readOnly, accountName: $accountName, accountType: $accountType, '
        'isPrimary: $isPrimary, hidden: $hidden)';
  }
}
