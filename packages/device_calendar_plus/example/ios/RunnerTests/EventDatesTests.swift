import XCTest

@testable import device_calendar_plus_ios

/// EventDates' resolution of the dates an updateEvent edit writes, under
/// device zones the iOS integration harness can't set (it runs the simulator
/// suite once, in the host's zone). A bare all-day toggle of a timed event
/// (isAllDay true, no new dates) writes the all-day span itself — the span
/// Android writes (#203) in #195's end convention — instead of leaving the
/// derivation to EventKit; explicit bounds pass through, an all-day end in
/// its stored form.
final class EventDatesTests: XCTestCase {
  private let utc = TimeZone(identifier: "UTC")!
  private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
  private let newYork = TimeZone(identifier: "America/New_York")!

  private func at(
    _ zone: TimeZone, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0
  ) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(
      from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
    )!
  }

  /// The last second of a calendar day in `zone`: where EventKit puts an
  /// all-day event's end.
  private func endOfDay(_ zone: TimeZone, _ month: Int, _ day: Int) -> Date {
    return at(zone, month, day, hour: 23, minute: 59).addingTimeInterval(59)
  }

  private func editedDates(
    start: Date,
    end: Date,
    newStart: Date? = nil,
    newEnd: Date? = nil,
    newIsAllDay: Bool,
    wasAllDay: Bool = false,
    deviceZone: TimeZone
  ) throws -> (start: Date?, end: Date?) {
    return try EventDates.resolveEditedDates(
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

  // MARK: - resolveEditedDates(...)

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
      start: at(losAngeles, 10, 22, hour: 23, minute: 30),
      end: at(losAngeles, 10, 23, minute: 30),
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
