import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// The save sequencing of `EventsService.detachThenFlipAllDay`: an occurrence
/// edit that flips the all-day flag saves twice, detach first, flip second
/// (#210, #212). The bug it works around is in EventKit's iCloud store, which
/// the simulator doesn't have, so these tests can't see it — they pin the
/// sequence instead, through a fake save step, so a "tidy" that collapses the
/// two saves back into one goes red here rather than only on a signed-in
/// iPhone. CONTRIBUTING ("The iCloud two-step save needs a signed-in iPhone")
/// has the device run that still covers the real behaviour.
final class DetachThenFlipAllDayTests: XCTestCase, DateFixtures {
  /// Records each save as the event stood when it was saved, and plays the
  /// part of EventKit's `isDetached`, which a test can't set on an `EKEvent`.
  private final class FakeSaves {
    struct Save {
      let span: EKSpan
      let title: String?
      let isAllDay: Bool
      let startDate: Date?
      let endDate: Date?
      let timeZone: TimeZone?
    }

    var saves: [Save] = []
    var resets = 0
    /// Whether the first save detaches the occurrence.
    var firstSaveDetaches = true
    /// The 1-based save that throws, if any.
    var throwingSave: Int?
    private var detached = false

    struct SaveFailed: Error {}

    func save(_ event: EKEvent, _ span: EKSpan) throws {
      saves.append(Save(
        span: span, title: event.title, isAllDay: event.isAllDay,
        startDate: event.startDate, endDate: event.endDate,
        timeZone: event.timeZone))
      if saves.count == throwingSave { throw SaveFailed() }
      if saves.count == 1 && firstSaveDetaches { detached = true }
    }

    func reset() { resets += 1 }

    func isDetached(_ event: EKEvent) -> Bool { detached }
  }

  private let fake = FakeSaves()

  /// A timed 09:00-10:00 occurrence in Los Angeles on 2026-03-10.
  private func timedOccurrence() -> EKEvent {
    let event = EKEvent(eventStore: EKEventStore())
    event.title = "Standup"
    event.timeZone = losAngeles
    event.startDate = at(losAngeles, 3, 10, hour: 9)
    event.endDate = at(losAngeles, 3, 10, hour: 10)
    return event
  }

  private func flip(
    _ event: EKEvent, to allDay: Bool, patch: [String: Any],
    dates: (start: Date?, end: Date?)
  ) -> Result<Void, CalendarError> {
    var args = patch
    args["isAllDay"] = allDay
    return EventsService.detachThenFlipAllDay(
      event, to: allDay, patch: EventFieldPatch(args: args), dates: dates,
      save: fake.save, reset: fake.reset, isDetached: fake.isDetached)
  }

  /// A bare flip of `timedOccurrence()` to all-day on its own day.
  private func flipTimedToAllDay() -> Result<Void, CalendarError> {
    flip(
      timedOccurrence(), to: true, patch: [:],
      dates: (at(.current, 3, 10), endOfDay(.current, 3, 10)))
  }

  /// The detach and flip saves. Throws (a test failure, not an out-of-range
  /// trap) when the sequence didn't save exactly twice; also fails unless
  /// each save was `.thisEvent`.
  private func twoSaves(
    file: StaticString = #filePath, line: UInt = #line
  ) throws -> (detach: FakeSaves.Save, flip: FakeSaves.Save) {
    XCTAssertEqual(
      fake.saves.map(\.span), [.thisEvent, .thisEvent],
      file: file, line: line)
    let saves = try XCTUnwrap(
      fake.saves.count == 2 ? fake.saves : nil,
      "expected exactly two saves, got \(fake.saves.count)",
      file: file, line: line)
    return (saves[0], saves[1])
  }

  private func assertOperationFailed(
    _ result: Result<Void, CalendarError>,
    file: StaticString = #filePath, line: UInt = #line,
    _ check: (CalendarError) -> Void = { _ in }
  ) {
    XCTAssertThrowsError(try result.get(), file: file, line: line) { error in
      guard let error = error as? CalendarError else {
        return XCTFail("not a CalendarError: \(error)", file: file, line: line)
      }
      XCTAssertEqual(
        error.code, PlatformExceptionCodes.operationFailed,
        file: file, line: line)
      check(error)
    }
  }

  // MARK: - timed to all-day

  /// Step 1 carries the fields and the all-day span as timed dates, still
  /// timed in its zone; step 2 is the flag, with the span and no zone.
  func testTimedToAllDayDetachesWithTheSpanThenFlipsTheFlag() throws {
    // An all-day span is the device zone's midnights, as `allDayToggleSpan`
    // builds it: EventKit snaps an all-day event's dates to those, so a span
    // in another zone reads back moved on a device outside it (CI is UTC).
    let start = at(.current, 3, 10)
    let end = endOfDay(.current, 3, 10)

    try flip(
      timedOccurrence(), to: true, patch: ["title": "Offsite"],
      dates: (start, end)
    ).get()

    let (detach, flipSave) = try twoSaves()
    XCTAssertEqual(fake.resets, 0)
    XCTAssertEqual(detach.title, "Offsite")
    XCTAssertFalse(detach.isAllDay)
    XCTAssertEqual(detach.startDate, start)
    XCTAssertEqual(detach.endDate, end)
    XCTAssertEqual(detach.timeZone, losAngeles)
    XCTAssertTrue(flipSave.isAllDay)
    XCTAssertEqual(flipSave.startDate, start)
    XCTAssertEqual(flipSave.endDate, end)
    XCTAssertNil(flipSave.timeZone)
  }

  // MARK: - all-day to timed

  /// Step 1 carries the fields and no timing change — the occurrence stays
  /// all-day on its own day, zone cleared; step 2 is the flag, with the
  /// timed hours and the zone.
  func testAllDayToTimedDetachesWithoutTheHoursThenFlipsTheFlag() throws {
    let event = EKEvent(eventStore: EKEventStore())
    event.title = "Holiday"
    event.isAllDay = true
    event.startDate = at(.current, 3, 10)
    event.endDate = endOfDay(.current, 3, 10)
    let allDayStart = event.startDate
    let allDayEnd = event.endDate
    let start = at(losAngeles, 3, 10, hour: 9)
    let end = at(losAngeles, 3, 10, hour: 10)

    try flip(
      event, to: false,
      patch: ["title": "Dentist", "timeZone": "America/Los_Angeles"],
      dates: (start, end)
    ).get()

    let (detach, flipSave) = try twoSaves()
    XCTAssertEqual(fake.resets, 0)
    XCTAssertEqual(detach.title, "Dentist")
    XCTAssertTrue(detach.isAllDay)
    XCTAssertEqual(detach.startDate, allDayStart)
    XCTAssertEqual(detach.endDate, allDayEnd)
    XCTAssertNil(detach.timeZone)
    XCTAssertFalse(flipSave.isAllDay)
    XCTAssertEqual(flipSave.startDate, start)
    XCTAssertEqual(flipSave.endDate, end)
    XCTAssertEqual(flipSave.timeZone, losAngeles)
  }

  // MARK: - failures

  /// A first save that leaves the occurrence attached resets the store and
  /// fails before the flip, which would otherwise be the one-save bug.
  func testFailsAfterAResetWithoutFlippingWhenStepOneDoesNotDetach() {
    fake.firstSaveDetaches = false

    let result = flipTimedToAllDay()

    XCTAssertEqual(fake.saves.count, 1)
    XCTAssertEqual(fake.resets, 1)
    assertOperationFailed(result)
  }

  /// A throwing first save fails the update and never reaches the flip.
  func testFailsWithoutFlippingWhenStepOneThrows() {
    fake.throwingSave = 1

    let result = flipTimedToAllDay()

    XCTAssertEqual(fake.saves.count, 1)
    XCTAssertEqual(fake.resets, 0)
    assertOperationFailed(result)
  }

  /// A throwing second save fails the update, saying the occurrence was left
  /// detached but unflipped.
  func testFailsSayingTheOccurrenceIsDetachedWhenStepTwoThrows() {
    fake.throwingSave = 2

    let result = flipTimedToAllDay()

    XCTAssertEqual(fake.saves.count, 2)
    assertOperationFailed(result) { error in
      XCTAssertTrue(error.message.contains("it is detached"), error.message)
    }
  }
}
