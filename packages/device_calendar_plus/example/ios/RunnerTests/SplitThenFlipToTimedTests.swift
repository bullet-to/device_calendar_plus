import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// The save sequencing of `EventsService.splitThenFlipToTimed`, the series
/// twin of `detachThenFlipAllDay`: a `thisAndFollowing` edit that flips an
/// all-day series timed splits in one staged save and flips in a second,
/// committing one (#232). These tests pin that sequence through a fake save
/// step, so folding the two saves back into one, or committing the first,
/// goes red here. CONTRIBUTING ("The iCloud two-step save needs a signed-in
/// iPhone") has the device run that covers the real behaviour.
final class SplitThenFlipToTimedTests: XCTestCase, DateFixtures {
  /// Records each save as the event stood when it was saved.
  private final class FakeSaves {
    struct Save {
      let span: EKSpan
      let commit: Bool
      let title: String?
      let isAllDay: Bool
      let startDate: Date?
      let endDate: Date?
      let hasRule: Bool
    }

    var saves: [Save] = []
    var resets = 0
    /// The 1-based save that throws, if any.
    var throwingSave: Int?
    /// Whether the first save comes back with the rule stripped.
    var splitStripsRule = false

    struct SaveFailed: Error {}

    func save(_ event: EKEvent, _ span: EKSpan, _ commit: Bool) throws {
      saves.append(Save(
        span: span, commit: commit, title: event.title,
        isAllDay: event.isAllDay, startDate: event.startDate,
        endDate: event.endDate,
        hasRule: event.recurrenceRules?.isEmpty == false))
      if saves.count == throwingSave { throw SaveFailed() }
      if saves.count == 1 && splitStripsRule { event.recurrenceRules = nil }
    }

    func reset() { resets += 1 }
  }

  private let fake = FakeSaves()

  private var weekly: EKRecurrenceRule {
    EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
  }

  /// An all-day occurrence on 2026-03-10 in the device zone.
  private func allDayOccurrence() -> EKEvent {
    let event = EKEvent(eventStore: EKEventStore())
    event.title = "Holiday"
    event.isAllDay = true
    event.startDate = at(.current, 3, 10)
    event.endDate = endOfDay(.current, 3, 10)
    return event
  }

  private func split(
    _ event: EKEvent, start: Date?, end: Date?
  ) -> Result<String, CalendarError> {
    EventsService.splitThenFlipToTimed(
      event,
      patch: EventFieldPatch(args: [
        "isAllDay": false, "title": "Dentist",
        "timeZone": "America/Los_Angeles",
      ]),
      splitRule: weekly, start: start, end: end, fallbackId: "fallback",
      save: fake.save, reset: fake.reset)
  }

  /// Step 1 is a staged `.futureEvents` save with the fields and the rule,
  /// still all-day on its own dates; step 2 commits the flip with the
  /// timed dates.
  func testStagesTheSplitWithTheFieldsThenCommitsTheFlip() throws {
    let event = allDayOccurrence()
    let allDayStart = event.startDate
    let allDayEnd = event.endDate
    let start = at(losAngeles, 3, 10, hour: 9)
    let end = at(losAngeles, 3, 10, hour: 10)

    XCTAssertEqual(try split(event, start: start, end: end).get(), "fallback")

    XCTAssertEqual(fake.saves.map(\.span), [.futureEvents, .futureEvents])
    XCTAssertEqual(fake.saves.map(\.commit), [false, true])
    XCTAssertEqual(fake.resets, 0)
    guard fake.saves.count == 2 else { return XCTFail("expected two saves") }
    let (splitSave, flipSave) = (fake.saves[0], fake.saves[1])
    XCTAssertEqual(splitSave.title, "Dentist")
    XCTAssertTrue(splitSave.hasRule)
    XCTAssertTrue(splitSave.isAllDay)
    XCTAssertEqual(splitSave.startDate, allDayStart)
    XCTAssertEqual(splitSave.endDate, allDayEnd)
    XCTAssertTrue(flipSave.hasRule)
    XCTAssertFalse(flipSave.isAllDay)
    XCTAssertEqual(flipSave.startDate, start)
    XCTAssertEqual(flipSave.endDate, end)
  }

  /// A throwing second save resets the store, so the staged split is
  /// discarded and nothing is written.
  func testResetsWhenTheFlipSaveThrows() {
    fake.throwingSave = 2

    let result = split(
      allDayOccurrence(),
      start: at(losAngeles, 3, 10, hour: 9),
      end: at(losAngeles, 3, 10, hour: 10))

    XCTAssertEqual(fake.saves.count, 2)
    XCTAssertEqual(fake.resets, 1)
    XCTAssertThrowsError(try result.get()) { error in
      XCTAssertEqual(
        (error as? CalendarError)?.code, PlatformExceptionCodes.operationFailed)
    }
  }

  /// A throwing first save resets and never reaches the flip.
  func testResetsWithoutFlippingWhenTheSplitSaveThrows() {
    fake.throwingSave = 1

    let result = split(allDayOccurrence(), start: nil, end: nil)

    XCTAssertEqual(fake.saves.count, 1)
    XCTAssertEqual(fake.resets, 1)
    XCTAssertThrowsError(try result.get()) { error in
      XCTAssertEqual(
        (error as? CalendarError)?.code, PlatformExceptionCodes.operationFailed)
    }
  }

  /// A split that comes back without its rule resets and fails before the
  /// flip, rather than flip on the un-rebased `splitRule`.
  func testResetsWithoutFlippingWhenTheSplitLosesItsRule() {
    fake.splitStripsRule = true

    let result = split(
      allDayOccurrence(),
      start: at(losAngeles, 3, 10, hour: 9),
      end: at(losAngeles, 3, 10, hour: 10))

    XCTAssertEqual(fake.saves.count, 1)
    XCTAssertEqual(fake.resets, 1)
    XCTAssertThrowsError(try result.get()) { error in
      XCTAssertEqual(
        (error as? CalendarError)?.code, PlatformExceptionCodes.operationFailed)
    }
  }
}
