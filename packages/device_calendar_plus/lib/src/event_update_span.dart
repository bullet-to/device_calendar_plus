/// Which occurrences of a recurring event an update applies to.
///
/// Used by [DeviceCalendar.updateRecurring] to choose the scope of an edit to
/// a recurring series.
enum EventUpdateSpan {
  /// The edit applies to every occurrence in the series — past and future.
  ///
  /// Clearing the recurrence rule with this span collapses the whole series
  /// into a single, non-recurring event.
  allEvents,

  /// The edit applies from the supplied occurrence onwards, leaving earlier
  /// occurrences untouched.
  ///
  /// The series is split at the occurrence timestamp carried by the instance
  /// ID: the original series is truncated and a new series is created for the
  /// affected occurrences.
  ///
  /// **Off-by-one:** the occurrence you name as the split point stays on the
  /// *original* series — the new series begins at the next occurrence. iOS
  /// EventKit behaves this way natively and Android is bent to match, so the
  /// behaviour is consistent and documented rather than divergent.
  thisAndFollowing,
}
