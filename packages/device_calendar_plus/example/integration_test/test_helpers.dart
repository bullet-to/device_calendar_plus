/// Shared helpers for the integration tests. Plain Dart, not a test entry:
/// `all_tests.dart` does not import it.
library;

/// Local midnight [daysFromNow] days from today. Built via the constructor
/// rather than `DateTime.add`, so the result is a calendar day rather than
/// 24 hours (which lands an hour off across a DST transition).
DateTime localMidnight(int daysFromNow) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + daysFromNow);
}
