import EventKit
import Foundation
import XCTest

@testable import device_calendar_plus_ios

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
