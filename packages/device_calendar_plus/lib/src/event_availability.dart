/// Availability status of a calendar event.
enum EventAvailability {
  /// Availability is busy (default for most events).
  ///
  /// Available on: Android, iOS
  busy,

  /// Availability is free (time is available despite event).
  ///
  /// Available on: Android, iOS
  free,

  /// Availability is tentative (event is not confirmed).
  ///
  /// Available on: Android, iOS
  tentative,

  /// Availability is unavailable (out of office, etc.).
  ///
  /// Available on: iOS only
  unavailable,

  /// Availability status is not supported or unknown.
  ///
  /// Available on: iOS only (when calendar doesn't support availability)
  notSupported;

  /// Safely parses a string to an EventAvailability enum.
  /// Returns [notSupported] if the value doesn't match any known case.
  static EventAvailability fromName(String name) {
    return EventAvailability.values.firstWhere(
      (e) => e.name == name,
      orElse: () => EventAvailability.notSupported,
    );
  }
}
