/// Which occurrences of a recurring event an operation applies to.
///
/// Used by [DeviceCalendar.updateRecurring] and
/// [DeviceCalendar.deleteRecurring] to choose the scope of a change to a
/// recurring series.
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

  /// The operation applies only to the supplied occurrence; the rest of the
  /// series is left untouched.
  ///
  /// This detaches that occurrence from the series as an exception. A
  /// recurrence rule cannot be set with this span — a single occurrence has
  /// no rule of its own.
  thisInstance,
}
