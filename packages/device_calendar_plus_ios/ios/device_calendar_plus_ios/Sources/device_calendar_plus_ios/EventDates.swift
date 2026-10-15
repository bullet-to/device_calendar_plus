import Foundation

/// The date arithmetic behind a one-thing (`updateEvent`) write: the dates
/// the edit writes, the all-day span a bare toggle gives a timed event, and
/// the all-day end convention EventKit stores (`allDayStoredEnd`), which
/// `SeriesDates.resolveSeriesEnd` follows in wall-clock seconds for a series
/// edit's all-day ends. Pure — the device zone is passed in rather than read
/// from `TimeZone.current`, so native tests can drive the zones the
/// integration harness can't set on iOS. Android's counterpart is
/// `EventTiming.kt` for the edited bounds; it keeps the all-day arithmetic
/// (the toggle span, the UTC-midnight conversions) in `AllDayDates.kt`.
enum EventDates {
  /// The dates an `updateEvent` edit writes for an event now at
  /// `start`–`end`, given the caller's optional `newStart`/`newEnd`, the
  /// all-day flag the edit leaves it with (`newIsAllDay`) and the one it has
  /// (`wasAllDay`). `nil` means "leave that bound as it is".
  ///
  /// A bare all-day toggle — `newIsAllDay` with no new dates, on a timed
  /// event — writes `allDayToggleSpan`, the span Android writes (#203), so
  /// the event covers exactly the local days its timed self touched.
  /// Otherwise each given bound is written as is, an all-day end in its
  /// stored form (`allDayStoredEnd`). Fails with `operationFailed` only when
  /// the calendar can't compute the toggle span. Android's counterpart is
  /// `resolveEditedBounds` in `EventTiming.kt`.
  static func resolveEditedDates(
    start: Date,
    end: Date,
    newStart: Date?,
    newEnd: Date?,
    newIsAllDay: Bool,
    wasAllDay: Bool,
    deviceZone: TimeZone
  ) -> Result<(start: Date?, end: Date?), CalendarError> {
    if newIsAllDay, !wasAllDay, newStart == nil, newEnd == nil {
      guard let span = allDayToggleSpan(start: start, end: end, deviceZone: deviceZone) else {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.operationFailed,
          message: "Could not compute the event's all-day span"
        ))
      }
      return .success((start: span.start, end: span.end))
    }
    return .success((
      start: newStart,
      end: newEnd.map { allDayStoredEnd($0, isAllDay: newIsAllDay) }
    ))
  }

  /// The dates a bare all-day toggle — `isAllDay` set true with no new dates
  /// — leaves a timed event with: midnight of the `deviceZone` day it starts
  /// on, through the last second of the last day it touches (its end's day,
  /// or the day before when it ends on a midnight; its own day when it has no
  /// span). `nil` only when the calendar can't compute the day after.
  ///
  /// Written explicitly so iOS conforms to the span Android writes
  /// (`AllDayDates.toggleSpan`, #203) in #195's end convention, instead of
  /// leaving the derivation to EventKit.
  private static func allDayToggleSpan(
    start: Date,
    end: Date,
    deviceZone: TimeZone
  ) -> (start: Date, end: Date)? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = deviceZone
    let firstDay = calendar.startOfDay(for: start)
    // The last moment the event occupies: an end on a midnight is exclusive,
    // so it doesn't reach that day; an empty span still occupies its start.
    let lastMoment = max(end.addingTimeInterval(-1), start)
    let lastDay = calendar.startOfDay(for: lastMoment)
    guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
      return nil
    }
    return (start: firstDay, end: allDayStoredEnd(dayAfter, isAllDay: true))
  }

  /// The end to write for an all-day event whose end is `end`, exclusive
  /// (the plugin's form: midnight after the last day). EventKit keeps an
  /// all-day event's end at the last second of its last day, and reads an
  /// exclusive midnight written onto an existing all-day event as one more
  /// day; the read path adds the second back. Timed ends pass through.
  static func allDayStoredEnd(_ end: Date, isAllDay: Bool) -> Date {
    return isAllDay ? end.addingTimeInterval(-1) : end
  }
}
