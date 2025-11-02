/// Status of a calendar event.
enum EventStatus {
  /// Event has no status or status is not set.
  ///
  /// Available on: Android, iOS
  none,

  /// Event is confirmed.
  ///
  /// Available on: Android, iOS
  confirmed,

  /// Event is tentative (not yet confirmed).
  ///
  /// Available on: Android, iOS
  tentative,

  /// Event has been canceled.
  ///
  /// Available on: Android, iOS
  canceled;

  /// Safely parses a string to an EventStatus enum.
  /// Returns [none] if the value doesn't match any known case.
  static EventStatus fromName(String name) {
    return EventStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => EventStatus.none,
    );
  }
}
