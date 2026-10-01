import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// The day-move check in `SeriesDates.resolveSeriesStart`: with no new rule,
/// the series' new start must be a day its existing rule generates (#189).
/// Timed series in one zone, so only the rule decides. Mirrors the Kotlin
/// `DayMoveConflictTest` case for case — the platforms must agree.
///
/// The new start is the base (the series start) shifted by the move from the
/// reference occurrence to the target, so the cases where the two differ
/// check the start that is written, not just the target.
///
/// The ordinal and BYMONTH cases are also covered end to end by the
/// integration suite. BYDAY with BYMONTHDAY is here because the plugin can't
/// create it (the typed API has no BYDAY+BYMONTHDAY shape and writes send
/// `toRruleString()`), so it only reaches `updateRecurring` on events made by
/// another app, which an integration test can't set up.
final class DayMoveConflictTests: XCTestCase, RecurrenceFixtures {
  /// Moves the occurrence at `reference` (the series start when nil) of a
  /// timed `rule` series that starts at `from` to `to`, keeping the rule.
  private func move(
    _ rule: EKRecurrenceRule, from: Date, to: Date, reference: Date? = nil
  ) -> Result<Date, CalendarError> {
    return SeriesDates.resolveSeriesStart(
      base: from,
      storedZone: stockholm,
      existingRule: rule,
      target: to,
      reference: reference ?? from,
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

  /// Weekly on Monday, Wednesday and Friday.
  private var mondayWednesdayFriday: EKRecurrenceRule {
    rule(.weekly, days: [EKWeekday.monday, .wednesday, .friday].map { EKRecurrenceDayOfWeek($0) })
  }

  // Mon 2 Nov 2026 -> Wed 4 Nov: another day the rule lists.
  func testAllowsAMoveOntoAnotherDayTheRuleGenerates() {
    let target = at(2026, 11, 4)
    XCTAssertEqual(
      try move(mondayWednesdayFriday, from: at(2026, 11, 2), to: target).get(), target
    )
  }

  // Mon 2 Nov 2026 -> Tue 3 Nov.
  func testRefusesAMoveOntoADayTheRuleSkips() {
    assertRefused(move(mondayWednesdayFriday, from: at(2026, 11, 2), to: at(2026, 11, 3)))
  }

  // The Wed 4 Nov occurrence of a series starting Mon 2 Nov moves to Fri 6
  // Nov: the start moves two days with it, onto Wed 4 Nov.
  func testAllowsALaterOccurrenceMoveThatKeepsTheStartOnTheRule() {
    XCTAssertEqual(
      try move(
        mondayWednesdayFriday, from: at(2026, 11, 2), to: at(2026, 11, 6),
        reference: at(2026, 11, 4)
      ).get(),
      at(2026, 11, 4)
    )
  }

  // The Fri 6 Nov occurrence moves to Mon 9 Nov, a day the rule generates,
  // but the start moves three days with it, onto Thu 5 Nov, which it doesn't.
  func testRefusesALaterOccurrenceMoveThatPushesTheStartOffTheRule() {
    assertRefused(move(
      mondayWednesdayFriday, from: at(2026, 11, 2), to: at(2026, 11, 9),
      reference: at(2026, 11, 6)
    ))
  }

  // A series another app anchored off its rule, on Tue 3 Nov: retiming its
  // Wed 4 Nov occurrence keeps the start on that Tuesday, which isn't a day
  // move, so it isn't refused.
  func testAllowsATimeOnlyMoveOfAStartTheRuleDoesntGenerate() {
    XCTAssertEqual(
      try move(
        mondayWednesdayFriday, from: at(2026, 11, 3), to: at(2026, 11, 4, hour: 15),
        reference: at(2026, 11, 4)
      ).get(),
      at(2026, 11, 3, hour: 15)
    )
  }

  // A series another app anchored off its rule, on Tue 3 Nov: retiming that
  // first occurrence on the same Tuesday isn't a day move, so it isn't
  // refused, though the rule doesn't generate the day.
  func testAllowsATimeOnlyMoveOfAnOffRuleFirstOccurrence() {
    let target = at(2026, 11, 3, hour: 15)
    XCTAssertEqual(
      try move(mondayWednesdayFriday, from: at(2026, 11, 3), to: target).get(), target
    )
  }

  // The Thu 26 Nov occurrence (4th Thursday) of a series starting Thu 22 Oct
  // moves to Thu 24 Dec (also a 4th Thursday), but the start moves 28 days
  // with it, onto Thu 19 Nov, the 3rd.
  func testRefusesALaterOccurrenceMoveThatPushesTheStartOffTheOrdinal() {
    let fourthThursday = rule(.monthly, days: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)])
    assertRefused(move(
      fourthThursday, from: at(2026, 10, 22), to: at(2026, 12, 24),
      reference: at(2026, 11, 26)
    ))
  }
}
