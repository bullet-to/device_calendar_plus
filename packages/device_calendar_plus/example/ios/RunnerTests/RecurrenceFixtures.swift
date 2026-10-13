import EventKit
import Foundation
import XCTest

@testable import device_calendar_plus_ios

/// Shared fixtures for the recurrence tests: the zones they frame series in,
/// dates built in them, a terse `EKRecurrenceRule` builder and the rules and
/// moves more than one case drives. Conform a test case to pick them up.
protocol RecurrenceFixtures {}

extension RecurrenceFixtures {
  var stockholm: TimeZone { TimeZone(identifier: "Europe/Stockholm")! }
  var utc: TimeZone { TimeZone(identifier: "UTC")! }
  var sydney: TimeZone { TimeZone(identifier: "Australia/Sydney")! }

  /// A date in Stockholm, at 10:00 unless `hour` is given.
  func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = stockholm
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  /// A date in `zone` in 2026, at midnight unless `hour` is given.
  func at(_ zone: TimeZone, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }

  /// Weekly on Monday, Wednesday and Friday.
  var mondayWednesdayFriday: EKRecurrenceRule {
    rule(.weekly, days: [EKWeekday.monday, .wednesday, .friday].map { EKRecurrenceDayOfWeek($0) })
  }

  /// Moves the occurrence at `reference` (the series start when nil) of a
  /// timed `rule` series in Stockholm that starts at `from` to `to`, keeping
  /// the rule: what `SeriesDates.resolveSeriesStart` writes for it.
  func resolveTimedMove(
    _ rule: EKRecurrenceRule, from: Date, to: Date, reference: Date? = nil
  ) -> Result<SeriesWrite, CalendarError> {
    return SeriesDates.resolveSeriesStart(
      base: from,
      storedZone: stockholm,
      target: to,
      reference: reference ?? from,
      isAllDay: false,
      ruleEdit: .keep(rule),
      deviceZone: stockholm
    )
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

/// Asserts `result` is an invalid-arguments refusal, as Kotlin's
/// `Result.assertRefused` (TestResults.kt) does.
func assertRefused<T>(
  _ result: Result<T, CalendarError>, file: StaticString = #filePath, line: UInt = #line
) {
  guard case .failure(let error) = result else {
    return XCTFail("expected a refusal, got \(result)", file: file, line: line)
  }
  XCTAssertEqual(error.code, PlatformExceptionCodes.invalidArguments, file: file, line: line)
}
