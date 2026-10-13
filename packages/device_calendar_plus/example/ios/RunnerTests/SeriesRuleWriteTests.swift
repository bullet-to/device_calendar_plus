import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// The rule half of `SeriesDates.resolveSeriesStart`: whether a series update
/// sets the kept rule on the event again (`SeriesRuleWrite.set`) or leaves the
/// loaded one — see `SeriesRuleWrite.set` (#194, #206). iOS-only, so no
/// Kotlin twin: only EventKit needs the kept rule set again to move or split a
/// day-pinning series. The start the same call resolves is covered by
/// `DayMoveConflictTests` (the day-move check) and `SeriesDatesTests` (the
/// frames).
final class SeriesRuleWriteTests: XCTestCase, RecurrenceFixtures {
  private let utc = TimeZone(identifier: "UTC")!
  private let sydney = TimeZone(identifier: "Australia/Sydney")!

  /// Whether the series update `result` resolves sets its rule on the event
  /// again rather than leaving the loaded one.
  private func setsRule(_ result: Result<SeriesWrite, CalendarError>) throws -> Bool {
    if case .set = try result.get().rule { return true }
    return false
  }

  /// Whether moving the occurrence at `reference` (the series start when nil)
  /// of a timed `rule` series that starts at `from` to `to`, keeping the
  /// rule, sets the rule again.
  private func resets(
    _ rule: EKRecurrenceRule, from: Date, to: Date, reference: Date? = nil
  ) throws -> Bool {
    return try setsRule(SeriesDates.resolveSeriesStart(
      base: from,
      storedZone: stockholm,
      target: to,
      reference: reference ?? from,
      isAllDay: false,
      ruleEdit: .keep(rule),
      deviceZone: stockholm
    ))
  }

  /// Weekly on Monday, Wednesday and Friday.
  private var mondayWednesdayFriday: EKRecurrenceRule {
    rule(.weekly, days: [EKWeekday.monday, .wednesday, .friday].map { EKRecurrenceDayOfWeek($0) })
  }

  /// Weekly on Monday and Tuesday.
  private var mondayTuesday: EKRecurrenceRule {
    rule(.weekly, days: [EKWeekday.monday, .tuesday].map { EKRecurrenceDayOfWeek($0) })
  }

  // MARK: - Timed moves

  // Mon 2 Nov 2026 -> Wed 4 Nov, another day the rule lists.
  func testADayMoveOfAPinnedRuleResetsTheRule() throws {
    XCTAssertTrue(try resets(mondayWednesdayFriday, from: at(2026, 11, 2), to: at(2026, 11, 4)))
  }

  // The Wed 4 Nov occurrence of a series starting Mon 2 Nov moves to Fri 6
  // Nov: the thisAndFollowing shape, where the reference isn't the start.
  func testALaterOccurrenceDayMoveOfAPinnedRuleResetsTheRule() throws {
    XCTAssertTrue(try resets(
      mondayWednesdayFriday, from: at(2026, 11, 2), to: at(2026, 11, 6),
      reference: at(2026, 11, 4)
    ))
  }

  // An ordinal rule pins days too: Thu 26 Nov 2026 -> Thu 24 Dec, both 4th
  // Thursdays.
  func testADayMoveOfAnOrdinalRuleResetsTheRule() throws {
    let fourthThursday = rule(.monthly, days: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)])
    XCTAssertTrue(try resets(fourthThursday, from: at(2026, 11, 26), to: at(2026, 12, 24)))
  }

  // A time-only move of a pinned rule moves natively.
  func testATimeOnlyMoveOfAPinnedRuleKeepsTheRuleAsLoaded() throws {
    XCTAssertFalse(
      try resets(mondayWednesdayFriday, from: at(2026, 11, 4), to: at(2026, 11, 4, hour: 15))
    )
  }

  // A rule that takes its day from the start moves natively.
  func testADayMoveOfAnImplicitRuleKeepsTheRuleAsLoaded() throws {
    XCTAssertFalse(try resets(rule(.weekly), from: at(2026, 11, 4), to: at(2026, 11, 6)))
  }

  // A cross-midnight retime changes the day, so it is a day move.
  func testACrossMidnightRetimeOfAPinnedRuleResetsTheRule() throws {
    XCTAssertTrue(
      try resets(mondayTuesday, from: at(2026, 11, 2, hour: 23), to: at(2026, 11, 3, hour: 1))
    )
  }

  // MARK: - All-day toggles

  // A toggle is a day move when the two frames disagree: the reference is
  // read in the stored frame and the target in the edit frame (the device
  // zone, for an all-day edit).

  /// A date in `zone` in 2026, at midnight unless `hour` is given.
  private func at(_ zone: TimeZone, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }

  /// Whether toggling a UTC-stored Mon/Tue series anchored at `base` all-day
  /// onto `target`, a Sydney midnight, with the rule kept, sets it again.
  private func toggleAllDayResets(base: Date, target: Date) throws -> Bool {
    return try setsRule(SeriesDates.resolveSeriesStart(
      base: base,
      storedZone: utc,
      target: target,
      reference: base,
      isAllDay: true,
      ruleEdit: .keep(mondayTuesday),
      deviceZone: sydney
    ))
  }

  // A UTC series at Mon 2 Nov 2026 23:00, already Tuesday in Sydney, toggled
  // all-day onto Sydney's Tue 3 Nov goes Monday to Tuesday, so it is a day
  // move.
  func testAllDayToggleOntoAnotherLocalDayResetsTheRule() throws {
    XCTAssertTrue(try toggleAllDayResets(base: at(utc, 11, 2, hour: 23), target: at(sydney, 11, 3)))
  }

  // The same series at Mon 2 Nov 10:00 UTC toggled all-day onto Sydney's
  // Mon 2 Nov: the same day in both frames, so the rule is left as loaded.
  func testAllDayToggleOnTheSameLocalDayKeepsTheRuleAsLoaded() throws {
    XCTAssertFalse(try toggleAllDayResets(base: at(utc, 11, 2, hour: 10), target: at(sydney, 11, 2)))
  }
}
