import 'dart:ui' show Color;

/// Represents a user's calendar
class Calendar {
  /// Identifier returned by the platform.
  final String id;

  /// User-facing label shown in native calendar pickers.
  final String name;

  /// Calendar color as a hex string in `#RRGGBB` format, if provided by the OS.
  final String? colorHex;

  /// Parsed [colorHex] as a Flutter [Color], or `null` if absent or unparseable.
  Color? get color {
    final hex = colorHex;
    if (hex == null) return null;
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length == 6 ? value | 0xFF000000 : value);
  }

  /// Whether edits are disallowed (subscribed/shared calendars, server-managed feeds, etc.).
  final bool readOnly;

  /// Account name or email that owns the calendar, when exposed by the platform.
  final String? accountName;

  /// Platform-specific account type (for example `com.google`, `CalDAV`, or `local` on Android).
  final String? accountType;

  /// Whether the calendar is the default destination for new events on that
  /// account/device.
  final bool isPrimary;

  /// Marks calendars hidden in the Android Calendar UI. iOS always reports `false`.
  final bool hidden;

  /// Creates an immutable calendar description.
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

  /// Builds a calendar object from a platform channel payload.
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

  /// Serializes the calendar back into a map for platform channel use.
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

  /// Returns a copy with selectively overridden fields.
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
