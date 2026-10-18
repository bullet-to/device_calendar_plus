import Foundation

/// Shared date fixtures for the date-driven tests (the pure date arithmetic
/// of `EventDates` and `SeriesDates`, and the save sequencing in
/// `DetachThenFlipAllDayTests`): the zones they drive, and dates built in a
/// given zone in 2026. Conform a test case to pick them up. `RecurrenceFixtures` is the
/// fixed-zone sibling for the recurrence-rule tests.
protocol DateFixtures {}

extension DateFixtures {
  var utc: TimeZone { TimeZone(identifier: "UTC")! }
  var losAngeles: TimeZone { TimeZone(identifier: "America/Los_Angeles")! }
  var newYork: TimeZone { TimeZone(identifier: "America/New_York")! }
  var sydney: TimeZone { TimeZone(identifier: "Australia/Sydney")! }

  /// `month`/`day` 2026 at `hour`:`minute` on `zone`'s wall clock.
  func at(
    _ zone: TimeZone, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0
  ) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(
      from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
    )!
  }

  /// The last second of a calendar day in `zone`: where EventKit puts an
  /// all-day event's end.
  func endOfDay(_ zone: TimeZone, _ month: Int, _ day: Int) -> Date {
    return at(zone, month, day, hour: 23, minute: 59).addingTimeInterval(59)
  }
}
