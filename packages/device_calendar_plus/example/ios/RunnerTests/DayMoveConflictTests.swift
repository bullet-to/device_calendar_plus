import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// `SeriesDates.dayMoveConflictsWithRule` decides whether moving a series'
/// anchor breaks a day-spec its rule pins (BYDAY, BYMONTHDAY, BYMONTH). Each
/// pinned part is checked on its own, matching Android's
/// `dayMoveConflictsWithRule`. The BYDAY+BYMONTH case is also covered end to
/// end by the integration suite; this file exists mainly for BYDAY with
/// BYMONTHDAY, which the plugin can't create (the typed API has no
/// BYDAY+BYMONTHDAY shape and writes send `toRruleString()`), so it only
/// reaches `updateRecurring` on events made by another app. An integration
/// test can't set that up; this also serves as a fast regression check on
/// all three parts.
final class DayMoveConflictTests: XCTestCase, RecurrenceFixtures {
  private func conflicts(_ rule: EKRecurrenceRule, from: Date, to: Date) -> Bool {
    return SeriesDates.dayMoveConflictsWithRule(
      rule: rule, reference: from, referenceZone: stockholm,
      target: to, targetZone: stockholm
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
