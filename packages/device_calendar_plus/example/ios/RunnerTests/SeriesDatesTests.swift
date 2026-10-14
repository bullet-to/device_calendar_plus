import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// SeriesDates' start/end resolution under device zones the iOS integration
/// harness can't set (it runs the simulator suite once, in the host's zone).
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

  /// An allEvents edit of a UTC-stored series anchored at `base`, moving it
  /// to `target`; `ruleEdit` keeps the Thursday rule unless given.
  private func resolve(
    base: Date,
    target: Date,
    isAllDay: Bool,
    ruleEdit: SeriesRuleEdit? = nil,
    deviceZone: TimeZone
  ) -> Result<Date, CalendarError> {
    return SeriesDates.resolveSeriesStart(
      base: base,
      storedZone: utc,
      target: target,
      reference: base,
      isAllDay: isAllDay,
      ruleEdit: ruleEdit ?? .keep(thursdays),
      splitsSeries: false,
      deviceZone: deviceZone
    )
  }

  // MARK: - resolveSeriesStart(...)

  // A series stored in UTC and toggled all-day. West of UTC the stored frame
  // snapped the anchor to the previous local day; east of it the conflict
  // check read the local-midnight target as the previous UTC day and refused
  // a same-day toggle.

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
    assertRefused(result)
  }

  // East of UTC with a new rule: the re-anchor reads the local-midnight
  // start in the local frame too. In UTC, Thursday's Sydney midnight is
  // Wednesday, and a BYDAY=TH walk would land on Friday locally.
  func testAllDayToggleEastOfUtcWithANewRuleKeepsTheLocalDay() {
    let result = resolve(
      base: at(sydney, 10, 1, hour: 12),
      target: at(sydney, 10, 1),
      isAllDay: true,
      ruleEdit: .replace(thursdays),
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
      ruleEdit: .replace(SeriesDatesTests.weekly(on: .friday)),
      deviceZone: sydney
    )
    XCTAssertEqual(try result.get(), at(sydney, 10, 2))
  }

  // The flip side of the east-of-UTC case, mirrored by Android's
  // AllDayStartFrameTest (timedToAllDayOntoNextLocalDayEastOfUtc): a
  // Wednesday-23:00-UTC series shows on Thursday in Sydney, but the weekday
  // it pins is the stored-zone one. Toggling it all-day onto the Thursday it
  // shows on lands on a day the rule doesn't generate, so it needs a new
  // rule like any other day move.
  func testAllDayToggleOntoTheNextLocalDayOfTheStoredDayIsRefused() {
    let result = resolve(
      base: at(utc, 9, 30, hour: 23),
      target: at(sydney, 10, 1),
      isAllDay: true,
      ruleEdit: .keep(SeriesDatesTests.weekly(on: .wednesday)),
      deviceZone: sydney
    )
    assertRefused(result)
  }

  // MARK: - resolveSeriesEnd(...) (#195)

  private let newYork = TimeZone(identifier: "America/New_York")!

  /// The last second of a calendar day in `zone`: where EventKit puts an
  /// all-day event's end.
  private func endOfDay(_ zone: TimeZone, _ month: Int, _ day: Int) -> Date {
    return at(zone, month, day, hour: 23).addingTimeInterval(59 * 60 + 59)
  }

  private func resolveEndResult(
    start: Date,
    end: Date,
    newStart: Date,
    startGiven: Bool = true,
    durationMinutes: Int?,
    isAllDay: Bool
  ) -> Result<Date?, CalendarError> {
    return SeriesDates.resolveSeriesEnd(
      start: start,
      end: end,
      newStart: newStart,
      startGiven: startGiven,
      durationMinutes: durationMinutes,
      isAllDay: isAllDay,
      deviceZone: newYork
    )
  }

  private func resolveEnd(
    start: Date,
    end: Date,
    newStart: Date,
    startGiven: Bool = true,
    durationMinutes: Int?,
    isAllDay: Bool
  ) -> Date? {
    return (try? resolveEndResult(
      start: start,
      end: end,
      newStart: newStart,
      startGiven: startGiven,
      durationMinutes: durationMinutes,
      isAllDay: isAllDay
    ).get()) ?? nil
  }

  // A change that moves nothing (no start or duration given, and a kept rule
  // that already fits its anchor) resolves no end, so the event's times
  // aren't rewritten (Android's rewriteTimeColumns skips the same case).
  func testNothingMovedResolvesNoEnd() {
    let start = at(newYork, 10, 1)
    let end = resolveEnd(
      start: start,
      end: endOfDay(newYork, 10, 1),
      newStart: start,
      startGiven: false,
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertNil(end)
  }

  // A given start resolves an end even when it lands on the current start.
  func testAGivenStartOnTheCurrentStartResolvesAnEnd() {
    let start = at(newYork, 10, 1)
    let end = resolveEnd(
      start: start,
      end: endOfDay(newYork, 10, 1),
      newStart: start,
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 10, 1))
  }

  // An all-day series only takes whole-day durations: the stored event's
  // all-day state is only known natively, so the Dart check can't catch it.
  func testAllDayPartialDayDurationIsRefused() {
    let result = resolveEndResult(
      start: at(newYork, 10, 1),
      end: endOfDay(newYork, 10, 1),
      newStart: at(newYork, 10, 15),
      durationMinutes: 1440 + 60,
      isAllDay: true
    )
    assertRefused(result)
  }

  // An all-day duration counts calendar days: two days from 31 October run
  // through 1 November, even though 1 November (DST end) is 25 hours long.
  // Adding 172,800 seconds stopped at 1 November 23:00, a day short. The end
  // is that last day's 23:59:59, where EventKit keeps an all-day end; an
  // exclusive midnight reads as one more day.
  func testAllDayDurationAcrossDstEndCountsCalendarDays() {
    let end = resolveEnd(
      start: at(newYork, 10, 24),
      end: endOfDay(newYork, 10, 24),
      newStart: at(newYork, 10, 31),
      durationMinutes: 2 * 1440,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 11, 1))
  }

  // And across DST start (8 March, 23 hours long) it doesn't overshoot into
  // the next day.
  func testAllDayDurationAcrossDstStartCountsCalendarDays() {
    let end = resolveEnd(
      start: at(newYork, 2, 28),
      end: endOfDay(newYork, 2, 28),
      newStart: at(newYork, 3, 7),
      durationMinutes: 2 * 1440,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 3, 8))
  }

  // With no duration, a moved all-day series keeps its span in calendar
  // days. Carried as seconds across DST start, a three-day span ending at
  // 23:59:59 ran an hour into a fourth day.
  func testAllDayKeptSpanAcrossDstStartKeepsItsDays() {
    let end = resolveEnd(
      start: at(newYork, 2, 28),
      end: endOfDay(newYork, 3, 2),
      newStart: at(newYork, 3, 7),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 3, 9))
  }

  // A kept span whose moved range ends on DST start (8 March, 23 hours
  // long) ends at that day's 23:59:59. Carrying the last day's time as
  // elapsed hours from its midnight ran an hour into 9 March.
  func testAllDayKeptSpanEndingOnDstStartEndsThatDay() {
    let end = resolveEnd(
      start: at(newYork, 2, 1),
      end: endOfDay(newYork, 2, 3),
      newStart: at(newYork, 3, 6),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 3, 8))
  }

  // And ending on DST end (1 November, 25 hours long) it keeps the last
  // hour rather than stopping at 22:59:59.
  func testAllDayKeptSpanEndingOnDstEndKeepsTheLastHour() {
    let end = resolveEnd(
      start: at(newYork, 2, 1),
      end: endOfDay(newYork, 2, 3),
      newStart: at(newYork, 10, 30),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 11, 1))
  }

  // A one-day span on DST start lasts 22:59:59 of elapsed time; moved to an
  // ordinary day it still ends at 23:59:59, not an hour short.
  func testAllDayKeptSpanFromADstStartDayKeepsItsWallClockEnd() {
    let end = resolveEnd(
      start: at(newYork, 3, 8),
      end: endOfDay(newYork, 3, 8),
      newStart: at(newYork, 3, 10),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 3, 10))
  }

  // A two-day span ending on DST end moved to ordinary days doesn't run an
  // hour into a third day.
  func testAllDayKeptSpanFromADstEndDayKeepsItsDays() {
    let end = resolveEnd(
      start: at(newYork, 10, 31),
      end: endOfDay(newYork, 11, 1),
      newStart: at(newYork, 11, 7),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, endOfDay(newYork, 11, 8))
  }

  // A timed event toggled all-day keeps its span from the new day's
  // midnight: a one-hour 10:00 event moved to 15 October ends at 01:00.
  func testTimedToAllDayKeptSpanRunsFromTheNewMidnight() {
    let end = resolveEnd(
      start: at(newYork, 10, 1, hour: 10),
      end: at(newYork, 10, 1, hour: 11),
      newStart: at(newYork, 10, 15),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, at(newYork, 10, 15, hour: 1))
  }

  // A given timed duration is an exact interval: two days from 31 October
  // 23:00 is 172,800 seconds later, whatever the wall clock reads, and it
  // replaces the stored one-hour span.
  func testTimedDurationAcrossDstEndIsExact() {
    let newStart = at(newYork, 10, 31, hour: 23)
    let end = resolveEnd(
      start: at(newYork, 10, 24, hour: 23),
      end: at(newYork, 10, 25),
      newStart: newStart,
      durationMinutes: 2 * 1440,
      isAllDay: false
    )
    XCTAssertEqual(end, newStart.addingTimeInterval(2 * 86_400))
  }

  // A kept timed span is the stored interval too: an all-day event toggled
  // timed and moved across DST end keeps its stored interval exactly (one
  // second short of a day), not the wall-clock span.
  func testTimedKeptSpanAcrossDstEndIsTheStoredInterval() {
    let newStart = at(newYork, 10, 31, hour: 23)
    let storedStart = at(newYork, 10, 24)
    let storedEnd = endOfDay(newYork, 10, 24)
    let keptEnd = resolveEnd(
      start: storedStart,
      end: storedEnd,
      newStart: newStart,
      durationMinutes: nil,
      isAllDay: false
    )
    XCTAssertEqual(
      keptEnd,
      newStart.addingTimeInterval(storedEnd.timeIntervalSince(storedStart))
    )
  }

  // A timed event toggled all-day whose wall-clock span runs backwards
  // across DST end (01:30 EDT to 01:10 EST, 40 minutes later) clamps to a
  // zero-length span at the new midnight, rather than ending the day before
  // it starts.
  func testAllDayKeptSpanRunningBackwardsAcrossDstEndClampsToTheNewStart() {
    let start = at(newYork, 11, 1).addingTimeInterval(90 * 60)
    let end = resolveEnd(
      start: start,
      end: start.addingTimeInterval(40 * 60),
      newStart: at(newYork, 11, 10),
      durationMinutes: nil,
      isAllDay: true
    )
    XCTAssertEqual(end, at(newYork, 11, 10))
  }

  // MARK: - resolveEditedDates(...)

  // The dates an updateEvent edit writes. A bare all-day toggle of a timed
  // event (isAllDay true, no new dates) writes the all-day span itself — the
  // span Android writes (#203) in #195's end convention — instead of leaving
  // the derivation to EventKit; explicit bounds pass through, an all-day end
  // in its stored form. The iCloud store's day-late end on a detach-plus-flip
  // is cured by the two-step save in EventsService.updateEvent, not by the
  // explicit span.

  private func editedDates(
    start: Date,
    end: Date,
    newStart: Date? = nil,
    newEnd: Date? = nil,
    newIsAllDay: Bool,
    wasAllDay: Bool = false,
    deviceZone: TimeZone
  ) throws -> (start: Date?, end: Date?) {
    return try SeriesDates.resolveEditedDates(
      start: start,
      end: end,
      newStart: newStart,
      newEnd: newEnd,
      newIsAllDay: newIsAllDay,
      wasAllDay: wasAllDay,
      deviceZone: deviceZone
    ).get()
  }

  /// A bare all-day toggle of a timed `start`–`end` event.
  private func toggleSpan(
    start: Date, end: Date, deviceZone: TimeZone
  ) throws -> (start: Date?, end: Date?) {
    return try editedDates(start: start, end: end, newIsAllDay: true, deviceZone: deviceZone)
  }

  // An event inside one day spans that day: local midnight through its
  // last second, where EventKit keeps an all-day end.
  func testToggleSpanOfAnEventWithinOneDayIsThatDay() throws {
    let span = try toggleSpan(
      start: at(losAngeles, 10, 22, hour: 9),
      end: at(losAngeles, 10, 22, hour: 10),
      deviceZone: losAngeles
    )
    XCTAssertEqual(span.start, at(losAngeles, 10, 22))
    XCTAssertEqual(span.end, endOfDay(losAngeles, 10, 22))
  }

  // An event that runs over midnight touches two days and spans both.
  func testToggleSpanOfAnEventOverMidnightSpansBothDays() throws {
    let span = try toggleSpan(
      start: at(losAngeles, 10, 22, hour: 23).addingTimeInterval(30 * 60),
      end: at(losAngeles, 10, 23).addingTimeInterval(30 * 60),
      deviceZone: losAngeles
    )
    XCTAssertEqual(span.start, at(losAngeles, 10, 22))
    XCTAssertEqual(span.end, endOfDay(losAngeles, 10, 23))
  }

  // An end on a midnight is exclusive: the event never touches that day.
  func testToggleSpanOfAnEventEndingOnMidnightStopsTheDayBefore() throws {
    let span = try toggleSpan(
      start: at(losAngeles, 10, 22, hour: 23),
      end: at(losAngeles, 10, 23),
      deviceZone: losAngeles
    )
    XCTAssertEqual(span.start, at(losAngeles, 10, 22))
    XCTAssertEqual(span.end, endOfDay(losAngeles, 10, 22))
  }

  // A zero-length event still gets its one day.
  func testToggleSpanOfAZeroLengthEventIsItsDay() throws {
    let start = at(losAngeles, 10, 22, hour: 23)
    let span = try toggleSpan(start: start, end: start, deviceZone: losAngeles)
    XCTAssertEqual(span.start, at(losAngeles, 10, 22))
    XCTAssertEqual(span.end, endOfDay(losAngeles, 10, 22))
  }

  // The days are the device zone's, not UTC's. The same instants — 17:00 to
  // 18:00 on 22 October in Los Angeles, already 23 October in UTC and
  // nowhere near a local midnight — land on the 22nd for a Los Angeles
  // device and on the 23rd for a UTC one.
  func testToggleSpanReadsTheDaysInTheDeviceZone() throws {
    let start = at(losAngeles, 10, 22, hour: 17)
    let end = at(losAngeles, 10, 22, hour: 18)
    XCTAssertEqual(start, at(utc, 10, 23), "the fixture must straddle a UTC date")

    let local = try toggleSpan(start: start, end: end, deviceZone: losAngeles)
    XCTAssertEqual(local.start, at(losAngeles, 10, 22))
    XCTAssertEqual(local.end, endOfDay(losAngeles, 10, 22))

    let utcFrame = try toggleSpan(start: start, end: end, deviceZone: utc)
    XCTAssertEqual(utcFrame.start, at(utc, 10, 23))
    XCTAssertEqual(utcFrame.end, endOfDay(utc, 10, 23))
  }

  // Across DST end (1 November, 25 hours long) the last second of the day
  // is still 23:59:59 on the wall clock, not 24 hours after midnight.
  func testToggleSpanAcrossDstEndEndsOnTheWallClock() throws {
    let span = try toggleSpan(
      start: at(newYork, 10, 31, hour: 22),
      end: at(newYork, 11, 1, hour: 3),
      deviceZone: newYork
    )
    XCTAssertEqual(span.start, at(newYork, 10, 31))
    XCTAssertEqual(span.end, endOfDay(newYork, 11, 1))
  }

  // Explicit bounds on an all-day edit pass through, the exclusive-midnight
  // end in EventKit's stored form: a 22–24 October write stores the end as
  // the last second of the 23rd (#195).
  func testExplicitAllDayEndIsStoredAsTheLastSecondOfItsDay() throws {
    let dates = try editedDates(
      start: at(losAngeles, 10, 22, hour: 9),
      end: at(losAngeles, 10, 22, hour: 10),
      newStart: at(losAngeles, 10, 22),
      newEnd: at(losAngeles, 10, 24),
      newIsAllDay: true,
      deviceZone: losAngeles
    )
    XCTAssertEqual(dates.start, at(losAngeles, 10, 22))
    XCTAssertEqual(dates.end, endOfDay(losAngeles, 10, 23))
  }

  // A timed edit writes the bound it was given and leaves the other alone.
  func testExplicitTimedStartPassesThroughAndLeavesTheEndAlone() throws {
    let dates = try editedDates(
      start: at(losAngeles, 10, 22, hour: 9),
      end: at(losAngeles, 10, 22, hour: 10),
      newStart: at(losAngeles, 10, 22, hour: 11),
      newIsAllDay: false,
      deviceZone: losAngeles
    )
    XCTAssertEqual(dates.start, at(losAngeles, 10, 22, hour: 11))
    XCTAssertNil(dates.end)
  }

  // isAllDay true on an event that already is all-day is not a toggle: with
  // no new dates, nothing is written.
  func testAllDayOnAnAllDayEventWithNoDatesWritesNone() throws {
    let dates = try editedDates(
      start: at(losAngeles, 10, 22),
      end: endOfDay(losAngeles, 10, 22),
      newIsAllDay: true,
      wasAllDay: true,
      deviceZone: losAngeles
    )
    XCTAssertNil(dates.start)
    XCTAssertNil(dates.end)
  }
}
