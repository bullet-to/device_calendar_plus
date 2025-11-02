/// Availability status of a calendar event.
enum EventAvailability {
  /// Availability is busy (default for most events).
  busy,

  /// Availability is free (time is available despite event).
  free,

  /// Availability is tentative (event is not confirmed).
  tentative,

  /// Availability is unavailable (out of office, etc.).
  unavailable,

  /// Availability status is not supported or unknown.
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
