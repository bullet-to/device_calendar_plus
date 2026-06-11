/// A time-of-day for a recurring event's occurrences.
///
/// The constructor validates its fields, so an [EventTimeOfDay] always holds
/// a real time-of-day. This matters at the platform layer: java.util.Calendar
/// on Android is lenient and would silently roll an out-of-range value into
/// the next day.
final class EventTimeOfDay {
  /// Creates a time-of-day.
  ///
  /// Throws [ArgumentError] unless [hour] is 0-23 and [minute] is 0-59.
  EventTimeOfDay({required this.hour, required this.minute}) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  }

  /// The hour of the day, 0-23.
  final int hour;

  /// The minute past the hour, 0-59.
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is EventTimeOfDay && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      'EventTimeOfDay($hour:${minute.toString().padLeft(2, '0')})';
}
