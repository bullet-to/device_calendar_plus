import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// The day-move check in `SeriesDates.resolveSeriesStart`: a start move with
/// no new rule is refused unless the existing rule generates the target's
/// day (#189). Timed series in one zone, so only the rule decides. Mirrors
/// the Kotlin `DayMoveConflictTest` case for case — the platforms must agree.
///
/// The ordinal and BYMONTH cases are also covered end to end by the
/// integration suite. BYDAY with BYMONTHDAY is here because the plugin can't
/// create it (the typed API has no BYDAY+BYMONTHDAY shape and writes send
/// `toRruleString()`), so it only reaches `updateRecurring` on events made by
/// another app, which an integration test can't set up.
final class DayMoveConflictTests: XCTestCase, RecurrenceFixtures {
  /// Moves a timed `rule` series anchored at `from` to `to`, keeping the
  /// rule.
  private func move(_ rule: EKRecurrenceRule, from: Date, to: Date) -> Result<Date, CalendarError> {
    return SeriesDates.resolveSeriesStart(
      base: from,
      storedZone: stockholm,
      existingRule: rule,
      target: to,
      reference: from,
      isAllDay: false,
      rule: nil,
      changingRule: false,
      deviceZone: stockholm
    )
  }

  private func assertRefused(
    _ result: Result<Date, CalendarError>, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard case .failure(let error) = result else {
      return XCTFail("expected the day move to be refused, got \(result)", file: file, line: line)
    }
    XCTAssertEqual(error.code, PlatformExceptionCodes.invalidArguments, file: file, line: line)
  }

  /// Yearly on the 4th Thursday of November.
  private var thanksgiving: EKRecurrenceRule {
    rule(.yearly, days: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)], months: [11])
  }

  // Thu 26 Nov 2026 (4th Thursday) -> Thu 19 Nov (3rd): the weekday and
  // month hold, but the rule doesn't generate the 3rd Thursday.
  func testRefusesAMoveToAnotherOrdinalOfTheWeekday() {
    assertRefused(move(thanksgiving, from: at(2026, 11, 26), to: at(2026, 11, 19)))
  }

  // Fri 30 Oct 2026 (last Friday) -> Fri 23 Oct.
  func testRefusesAMoveOffTheLastWeekday() {
    let lastFriday = rule(.monthly, days: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)])
    assertRefused(move(lastFriday, from: at(2026, 10, 30), to: at(2026, 10, 23)))
  }

  // The last weekday of the month: Fri 30 Oct 2026 -> Fri 23 Oct.
  func testRefusesAMoveOffTheSetPosition() {
    let weekdays: [EKRecurrenceDayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday]
      .map { EKRecurrenceDayOfWeek($0) }
    let lastWeekday = rule(.monthly, days: weekdays, setPositions: [-1])
    assertRefused(move(lastWeekday, from: at(2026, 10, 30), to: at(2026, 10, 23)))
  }

  // Thu 26 Nov 2026 -> Thu 3 Dec: the weekday holds, BYMONTH=11 doesn't.
  func testRefusesAMoveOutOfThePinnedMonth() {
    assertRefused(move(thanksgiving, from: at(2026, 11, 26), to: at(2026, 12, 3)))
  }

  // Fri 13 Nov 2026 -> Fri 20 Nov: the weekday holds, BYMONTHDAY=13 doesn't.
  func testRefusesAMoveOffThePinnedDayOfMonth() {
    let fridayThe13th = rule(.monthly, days: [EKRecurrenceDayOfWeek(.friday)], daysOfMonth: [13])
    assertRefused(move(fridayThe13th, from: at(2026, 11, 13), to: at(2026, 11, 20)))
  }

  func testAllowsATimeOnlyMove() {
    let target = at(2026, 11, 26, hour: 15)
    XCTAssertEqual(try move(thanksgiving, from: at(2026, 11, 26), to: target).get(), target)
  }

  // A rule that pins no day follows its anchor anywhere.
  func testAllowsADayMoveOnARuleThatPinsNoDay() {
    let target = at(2026, 11, 19)
    XCTAssertEqual(try move(rule(.monthly), from: at(2026, 11, 26), to: target).get(), target)
  }
}
