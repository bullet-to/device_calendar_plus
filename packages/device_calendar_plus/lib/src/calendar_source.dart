/// Type of a calendar source/account.
enum CalendarSourceType {
  /// On-device only, not synced to any cloud service.
  ///
  /// Available on: Android, iOS
  local,

  /// CalDAV protocol (iCloud, Google, Fastmail, etc.).
  ///
  /// Available on: Android, iOS
  calDav,

  /// Microsoft Exchange / ActiveSync.
  ///
  /// Available on: Android, iOS
  exchange,

  /// Read-only subscribed calendar feeds (.ics).
  ///
  /// Available on: iOS only
  subscribed,

  /// System contacts birthdays (read-only).
  ///
  /// Available on: iOS only
  birthdays,

  /// Unknown or platform-specific sync adapter.
  ///
  /// Available on: Android, iOS
  other;

  /// Safely parses a string to a CalendarSourceType enum.
  /// Returns [other] if the value doesn't match any known case.
  static CalendarSourceType fromName(String name) {
    return CalendarSourceType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => CalendarSourceType.other,
    );
  }
}

/// Represents a calendar source/account that can own calendars.
///
/// Use [DeviceCalendar.listSources] to discover available sources, then pass
/// a source's [id] to [CreateCalendarOptionsIos] or use [accountName] +
/// [accountType] with [CreateCalendarOptionsAndroid] to create calendars under
/// a specific account.
class CalendarSource {
  /// Stable identifier for this source.
  ///
  /// - **iOS**: `EKSource.sourceIdentifier` — use with [CreateCalendarOptionsIos]
  /// - **Android**: Synthetic `"accountName|accountType"` — informational only,
  ///   not used for creation. Use [accountName] + [accountType] with
  ///   [CreateCalendarOptionsAndroid] instead.
  final String id;

  /// Display name or account identifier for this source.
  ///
  /// - **iOS**: `EKSource.title` (e.g. "iCloud", "Gmail")
  /// - **Android**: `ACCOUNT_NAME` (e.g. "user@gmail.com", "local")
  ///
  /// Matches [Calendar.accountName].
  final String accountName;

  /// Raw platform type string for this source.
  ///
  /// - **iOS**: e.g. "caldav", "local", "exchange"
  /// - **Android**: e.g. "com.google", "LOCAL", "com.android.exchange"
  ///
  /// Matches [Calendar.accountType].
  final String accountType;

  /// Normalized source type.
  final CalendarSourceType type;

  /// Whether this source supports calendar creation from this app.
  ///
  /// - **iOS**: true for local, CalDAV, and Exchange sources
  /// - **Android**: true only for local accounts (other account types are
  ///   managed by their sync adapters and may reject third-party calendars)
  final bool supportsCalendarCreation;

  const CalendarSource({
    required this.id,
    required this.accountName,
    required this.accountType,
    required this.type,
    required this.supportsCalendarCreation,
  });

  factory CalendarSource.fromMap(Map<String, dynamic> map) {
    return CalendarSource(
      id: map['id'] as String,
      accountName: map['accountName'] as String,
      accountType: map['accountType'] as String,
      type: CalendarSourceType.fromName(map['type'] as String? ?? 'other'),
      supportsCalendarCreation:
          map['supportsCalendarCreation'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'accountName': accountName,
      'accountType': accountType,
      'type': type.name,
      'supportsCalendarCreation': supportsCalendarCreation,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarSource &&
        other.id == id &&
        other.accountName == accountName &&
        other.accountType == accountType &&
        other.type == type &&
        other.supportsCalendarCreation == supportsCalendarCreation;
  }

  @override
  int get hashCode =>
      Object.hash(id, accountName, accountType, type, supportsCalendarCreation);

  @override
  String toString() =>
      'CalendarSource(id: $id, accountName: $accountName, accountType: $accountType, type: $type)';
}
