import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// `RecurrenceAnchor.firstMatch` picks the start for a rule change: the first
/// day on or after the intended anchor that the new rule generates, keeping
/// the anchor's wall-clock time in the event's timezone (#140). Mirrors the
/// Kotlin `RecurrenceAnchorTest` case for case — the platforms must agree.
final class RecurrenceAnchorTests: XCTestCase {
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

  private func firstMatch(_ rule: EKRecurrenceRule, from: Date) -> Date? {
    return RecurrenceAnchor.firstMatch(of: rule, onOrAfter: from, timeZone: stockholm)
  }

  private let weekdays: [EKRecurrenceDayOfWeek] = [
    .init(.monday), .init(.tuesday), .init(.wednesday), .init(.thursday), .init(.friday),
  ]

  // The #140 report: a Saturday series switched to Sundays must anchor on
  // the Sunday after the split occurrence, not stay on the Saturday.
  func testWeeklyByDayAnchorOffRuleMovesToNextListedWeekday() {
    XCTAssertEqual(
      firstMatch(rule(.weekly, days: [EKRecurrenceDayOfWeek(.sunday)]), from: at(2026, 9, 12)),
      at(2026, 9, 13)
    )
  }

  func testMonthlyByMonthDayPastThisMonthsDayMovesToNextMonth() {
    XCTAssertEqual(
      firstMatch(rule(.monthly, daysOfMonth: [15]), from: at(2026, 9, 20)),
      at(2026, 10, 15)
    )
  }

  // Negative BYMONTHDAY counts back from the end of the month.
  func testMonthlyByMonthDayNegativeMovesToLastDayOfMonth() {
    XCTAssertEqual(
      firstMatch(rule(.monthly, daysOfMonth: [-1]), from: at(2026, 9, 12)),
      at(2026, 9, 30)
    )
  }

  // September 2026's second Tuesday (the 8th) is already past, so the anchor
  // lands on October's (the 13th).
  func testMonthlyByDayOrdinalMovesToNthWeekdayOfNextMonth() {
    XCTAssertEqual(
      firstMatch(
        rule(.monthly, days: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)]),
        from: at(2026, 9, 12)
      ),
      at(2026, 10, 13)
    )
  }

  func testMonthlyByDayNegativeOrdinalMovesToLastWeekdayOfMonth() {
    XCTAssertEqual(
      firstMatch(
        rule(.monthly, days: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)]),
        from: at(2026, 9, 12)
      ),
      at(2026, 9, 25)
    )
  }

  // Per RFC 5545 BYDAY limits a BYMONTHDAY set rather than expanding it:
  // "Friday the 13th" skips October's Tuesday 13th for November's Friday.
  func testMonthlyByMonthDayAndByDayByDayLimitsTheSet() {
    XCTAssertEqual(
      firstMatch(
        rule(.monthly, days: [EKRecurrenceDayOfWeek(.friday)], daysOfMonth: [13]),
        from: at(2026, 9, 12)
      ),
      at(2026, 11, 13)
    )
  }

  // "First weekday of the month": a positive BYSETPOS counts from the start
  // of the BYDAY set, so the anchor is Thursday 1 October.
  func testMonthlyBySetPosPositiveSelectsFromTheStartOfTheSet() {
    XCTAssertEqual(
      firstMatch(rule(.monthly, days: weekdays, setPositions: [1]), from: at(2026, 9, 12)),
      at(2026, 10, 1)
    )
  }

  func testYearlyByMonthAndMonthDayMovesToThatDateThisYear() {
    XCTAssertEqual(
      firstMatch(rule(.yearly, daysOfMonth: [25], months: [12]), from: at(2026, 9, 12)),
      at(2026, 12, 25)
    )
  }

  // With no BYMONTHDAY the day-of-month is the anchor's, as the start date
  // would supply it — the 12th of December, not the 1st.
  func testYearlyByMonthOnlyKeepsAnchorsDayOfMonth() {
    XCTAssertEqual(
      firstMatch(rule(.yearly, months: [12]), from: at(2026, 9, 12)),
      at(2026, 12, 12)
    )
  }

  // With no BYMONTH the month is the anchor's, as the start date would supply
  // it (RFC 5545 would expand across every month): the 15th of September is
  // past, so the anchor is next September's, not 15 October.
  func testYearlyByMonthDayOnlyKeepsAnchorsMonth() {
    XCTAssertEqual(
      firstMatch(rule(.yearly, daysOfMonth: [15]), from: at(2026, 9, 20)),
      at(2027, 9, 15)
    )
  }

  func testYearlyLeapDayLooksAheadToTheNextLeapYear() {
    XCTAssertEqual(
      firstMatch(rule(.yearly, daysOfMonth: [29], months: [2]), from: at(2026, 3, 1)),
      at(2028, 2, 29)
    )
  }

  // With BYMONTH, a BYDAY ordinal counts within the month (last Monday of
  // May), not within the year.
  func testYearlyByMonthAndOrdinalByDayCountsWithinTheMonth() {
    XCTAssertEqual(
      firstMatch(
        rule(.yearly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: -1)], months: [5]),
        from: at(2026, 9, 12)
      ),
      at(2027, 5, 31)
    )
  }

  // BYDAY alone on a yearly rule counts within the year: 2026's second
  // Monday (12 January) is past, so the anchor is 2027's (11 January).
  func testYearlyByDayOnlyOrdinalCountsWithinTheYear() {
    XCTAssertEqual(
      firstMatch(
        rule(.yearly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 2)]),
        from: at(2026, 9, 12)
      ),
      at(2027, 1, 11)
    )
  }

  // "Last weekday of January": BYSETPOS picks from the year's set, which
  // BYMONTH narrows to January's weekdays — Friday 29 January 2027.
  func testYearlyBySetPosSelectsFromTheYearsSet() {
    XCTAssertEqual(
      firstMatch(
        rule(.yearly, days: weekdays, months: [1], setPositions: [-1]), from: at(2026, 9, 12)
      ),
      at(2027, 1, 29)
    )
  }

  // "Last weekday of the month": BYSETPOS picks from the BYDAY set, so the
  // anchor is Wednesday 30 September, not the next weekday after the 12th.
  func testMonthlyBySetPosSelectsFromTheExpandedSet() {
    XCTAssertEqual(
      firstMatch(rule(.monthly, days: weekdays, setPositions: [-1]), from: at(2026, 9, 12)),
      at(2026, 9, 30)
    )
  }

  // In a DAILY rule BYDAY only filters: Saturday the 12th skips to Monday.
  func testDailyByDayFiltersToTheNextListedWeekday() {
    XCTAssertEqual(
      firstMatch(
        rule(.daily, days: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.wednesday)]),
        from: at(2026, 9, 12)
      ),
      at(2026, 9, 14)
    )
  }

  // An anchor the rule already generates is returned untouched, so a rule
  // change that keeps the day never moves the series.
  func testAnchorOnRuleIsUnchanged() {
    let saturday = at(2026, 9, 12)
    XCTAssertEqual(
      firstMatch(rule(.weekly, days: [EKRecurrenceDayOfWeek(.saturday)]), from: saturday),
      saturday
    )
  }

  // Rules with no day spec take it from the anchor, so they fit any anchor.
  func testImplicitRulesFitAnyAnchor() {
    let the31st = at(2026, 10, 31)
    XCTAssertEqual(firstMatch(rule(.monthly), from: the31st), the31st)
    XCTAssertEqual(firstMatch(rule(.weekly), from: the31st), the31st)
    XCTAssertEqual(firstMatch(rule(.yearly), from: the31st), the31st)
  }

  // Stockholm falls back on 2026-10-25, so Sunday 10:00 is 25 hours after
  // Saturday 10:00 — the walk must keep the wall-clock time, not add 24h.
  func testCrossingDstKeepsWallClockTime() {
    XCTAssertEqual(
      firstMatch(rule(.weekly, days: [EKRecurrenceDayOfWeek(.sunday)]), from: at(2026, 10, 24)),
      at(2026, 10, 25)
    )
    XCTAssertEqual(at(2026, 10, 25).timeIntervalSince(at(2026, 10, 24)), 25 * 3600)
  }

  // 30 February never comes, so the walk gives up rather than looping — and
  // the caller refuses the rule instead of anchoring off it.
  func testRuleThatNeverGeneratesReturnsNil() {
    XCTAssertNil(
      firstMatch(rule(.yearly, daysOfMonth: [30], months: [2]), from: at(2026, 9, 12))
    )
  }
}
