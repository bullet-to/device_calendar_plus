import EventKit
import Foundation

/// Shared fixtures for the recurrence tests: a fixed zone, dates built in it,
/// and a terse `EKRecurrenceRule` builder. Conform a test case to pick them up.
protocol RecurrenceFixtures {}

extension RecurrenceFixtures {
  var stockholm: TimeZone { TimeZone(identifier: "Europe/Stockholm")! }

  func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = stockholm
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  func rule(
    _ frequency: EKRecurrenceFrequency,
    days: [EKRecurrenceDayOfWeek]? = nil,
    daysOfMonth: [Int]? = nil,
    months: [Int]? = nil,
    setPositions: [Int]? = nil
  ) -> EKRecurrenceRule {
    return EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: 1,
      daysOfTheWeek: days,
      daysOfTheMonth: daysOfMonth?.map { NSNumber(value: $0) },
      monthsOfTheYear: months?.map { NSNumber(value: $0) },
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: setPositions?.map { NSNumber(value: $0) },
      end: nil
    )
  }
}
