/// Status of a calendar event.
enum EventStatus {
  /// Event has no status or status is not set.
  none,

  /// Event is confirmed.
  confirmed,

  /// Event is tentative (not yet confirmed).
  tentative,

  /// Event has been canceled.
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
