import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// `SeriesDates.resolveSeriesStart` on a series stored in UTC and toggled
/// all-day, under device zones the integration harness can't set on iOS (it
/// runs the simulator suite once, in the host's zone). West of UTC the
/// stored frame snapped the anchor to the previous local day; east of it the
/// conflict check read the local-midnight target as the previous UTC day and
/// refused a same-day toggle.
final class SeriesDatesTests: XCTestCase {
  private let utc = TimeZone(identifier: "UTC")!
  private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
  private let sydney = TimeZone(identifier: "Australia/Sydney")!

  private func at(_ zone: TimeZone, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }

  /// FREQ=WEEKLY;BYDAY=<day>.
  private static func weekly(on day: EKWeekday) -> EKRecurrenceRule {
    return EKRecurrenceRule(
      recurrenceWith: .weekly,
      interval: 1,
      daysOfTheWeek: [EKRecurrenceDayOfWeek(day)],
      daysOfTheMonth: nil,
      monthsOfTheYear: nil,
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: nil,
      end: nil
    )
  }

  /// FREQ=WEEKLY;BYDAY=TH — 1 October 2026 is a Thursday.
  private let thursdays = SeriesDatesTests.weekly(on: .thursday)

  /// An allEvents edit of a UTC-stored Thursday series anchored at `base`,
  /// moving it to `target`, optionally with a new `rule`.
  private func resolve(
    base: Date,
    target: Date,
    isAllDay: Bool,
    rule: EKRecurrenceRule? = nil,
    changingRule: Bool = false,
    deviceZone: TimeZone
  ) -> Result<Date, CalendarError> {
    return SeriesDates.resolveSeriesStart(
      base: base,
      storedZone: utc,
      existingRule: thursdays,
      target: target,
      reference: base,
      isAllDay: isAllDay,
      rule: rule,
      changingRule: changingRule,
      deviceZone: deviceZone
    )
  }

  // MARK: - resolveSeriesStart(...)

  // West of UTC: local noon Thursday toggled to Thursday's local midnight
  // must stay on Thursday, not snap to UTC midnight (Wednesday locally).
  func testAllDayToggleWestOfUtcKeepsTheLocalDay() {
    let result = resolve(
      base: at(losAngeles, 10, 1, hour: 12),
      target: at(losAngeles, 10, 1),
      isAllDay: true,
      deviceZone: losAngeles
    )
    XCTAssertEqual(try result.get(), at(losAngeles, 10, 1))
  }

  // East of UTC: Thursday's local midnight is still Wednesday in UTC, but
  // the target is read in the post-edit (local) frame, so it's the same day.
  func testAllDayToggleEastOfUtcIsNotRefused() {
    let result = resolve(
      base: at(sydney, 10, 1, hour: 12),
      target: at(sydney, 10, 1),
      isAllDay: true,
      deviceZone: sydney
    )
    XCTAssertEqual(try result.get(), at(sydney, 10, 1))
  }

  // A timed edit keeps the stored frame: 01:00 UTC Friday is Thursday
  // evening in Los Angeles, but the series lives in UTC, so the move
  // changes its pinned weekday and is refused.
  func testTimedEditReadsTheTargetInTheStoredZone() {
    let result = resolve(
      base: at(utc, 10, 1, hour: 23),
      target: at(utc, 10, 2, hour: 1),
      isAllDay: false,
      deviceZone: losAngeles
    )
    guard case .failure(let error) = result else {
      return XCTFail("expected the day move to be refused, got \(result)")
    }
    XCTAssertEqual(error.code, PlatformExceptionCodes.invalidArguments)
  }

  // East of UTC with a new rule: the re-anchor reads the local-midnight
  // start in the local frame too. In UTC, Thursday's Sydney midnight is
  // Wednesday, and a BYDAY=TH walk would land on Friday locally.
  func testAllDayToggleEastOfUtcWithANewRuleKeepsTheLocalDay() {
    let result = resolve(
      base: at(sydney, 10, 1, hour: 12),
      target: at(sydney, 10, 1),
      isAllDay: true,
      rule: thursdays,
      changingRule: true,
      deviceZone: sydney
    )
    XCTAssertEqual(try result.get(), at(sydney, 10, 1))
  }

  // A new rule that doesn't generate the target's day walks to the first
  // local day it does: Thursday's Sydney midnight onto Friday's, not
  // Saturday's (where a UTC-frame walk from Wednesday 14:00 UTC ends up).
  func testAllDayToggleEastOfUtcWalksANewRuleInTheLocalFrame() {
    let result = resolve(
      base: at(sydney, 10, 1, hour: 12),
      target: at(sydney, 10, 1),
      isAllDay: true,
      rule: SeriesDatesTests.weekly(on: .friday),
      changingRule: true,
      deviceZone: sydney
    )
    XCTAssertEqual(try result.get(), at(sydney, 10, 2))
  }
}
