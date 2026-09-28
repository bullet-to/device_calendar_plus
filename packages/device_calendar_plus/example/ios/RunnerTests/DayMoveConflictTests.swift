import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// `EventsService.dayMoveConflictsWithRule` decides whether moving a series'
/// anchor breaks a day-spec its rule pins (BYDAY, BYMONTHDAY, BYMONTH). Each
/// pinned part is checked on its own, matching Android's
/// `dayMoveConflictsWithRule`.
final class DayMoveConflictTests: XCTestCase {
  private let stockholm = TimeZone(identifier: "Europe/Stockholm")!

  private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = stockholm
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private func rule(
    _ frequency: EKRecurrenceFrequency,
    days: [EKRecurrenceDayOfWeek]? = nil,
    daysOfMonth: [Int]? = nil,
    months: [Int]? = nil
  ) -> EKRecurrenceRule {
    return EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: 1,
      daysOfTheWeek: days,
      daysOfTheMonth: daysOfMonth?.map { NSNumber(value: $0) },
      monthsOfTheYear: months?.map { NSNumber(value: $0) },
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: nil,
      end: nil
    )
  }

  private func conflicts(_ rule: EKRecurrenceRule, from: Date, to: Date) -> Bool {
    return EventsService.dayMoveConflictsWithRule(
      rule: rule, reference: from, target: to, timeZone: stockholm
    )
  }

  func testConflictsWhenMoveKeepsWeekdayButChangesPinnedMonth() {
    // Yearly on the 4th Thursday of November. Thu 26 Nov 2026 -> Thu 3 Dec
    // 2026: the weekday holds, but BYMONTH=11 does not.
    let thanksgiving = rule(
      .yearly, days: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)], months: [11]
    )
    XCTAssertTrue(conflicts(thanksgiving, from: at(2026, 11, 26), to: at(2026, 12, 3)))
  }

  func testConflictsWhenMoveKeepsWeekdayButChangesPinnedDayOfMonth() {
    // Monthly on Friday the 13th. Fri 13 Nov 2026 -> Fri 20 Nov 2026: the
    // weekday holds, but BYMONTHDAY=13 does not.
    let fridayThe13th = rule(
      .monthly, days: [EKRecurrenceDayOfWeek(.friday)], daysOfMonth: [13]
    )
    XCTAssertTrue(conflicts(fridayThe13th, from: at(2026, 11, 13), to: at(2026, 11, 20)))
  }

  func testNoConflictWhenEveryPinnedPartHolds() {
    // Only the time of day moves, so weekday, day-of-month and month all hold.
    let pinned = rule(
      .yearly, days: [EKRecurrenceDayOfWeek(.friday)], daysOfMonth: [13], months: [11]
    )
    XCTAssertFalse(
      conflicts(pinned, from: at(2026, 11, 13), to: at(2026, 11, 13, hour: 15))
    )
  }
}
