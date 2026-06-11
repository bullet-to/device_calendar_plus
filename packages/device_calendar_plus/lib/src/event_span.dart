/// Which occurrences of a recurring event a series-level operation applies
/// to.
///
/// Used by [DeviceCalendar.updateRecurring] and
/// [DeviceCalendar.deleteRecurring] to choose the scope of a change to a
/// recurring series. To act on a single occurrence, pass its instance ID to
/// [DeviceCalendar.updateEvent] or [DeviceCalendar.deleteEvent] instead.
enum EventSpan {
  /// The operation applies to every occurrence in the series — past and
  /// future.
  ///
  /// Clearing the recurrence rule with this span collapses the whole series
  /// into a single, non-recurring event. Deleting with this span removes the
  /// whole series.
  allEvents,

  /// The operation applies to the supplied occurrence and every occurrence
  /// after it; earlier occurrences are left untouched.
  ///
  /// The series is split at the occurrence timestamp carried by the instance
  /// ID: the original series is truncated to end just before that occurrence,
  /// and the occurrence and every later one carry the change.
  thisAndFollowing,
}
