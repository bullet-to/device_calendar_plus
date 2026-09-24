import XCTest

@testable import device_calendar_plus_ios

/// `CalendarService.readOnlyRefusal` is the iOS half of #126: the guard that
/// turns a rename or delete of a calendar EventKit won't touch into `readOnly`
/// instead of the `operationFailed` a thrown save becomes. Only the one cell
/// that encodes a product decision is pinned here; the rest of the two-flag
/// OR reads off the page.
final class CalendarServiceTests: XCTestCase {

  // MARK: - readOnlyRefusal(isImmutable:allowsContentModifications:title:)

  /// The superset cell: EventKit says the calendar itself can't be edited or
  /// deleted even though events can still be added, so `listCalendars` calls
  /// it writable and the mutations still refuse it. This is the contract the
  /// `deleteCalendar` docs describe, and the one a "simplification" back to
  /// `allowsContentModifications` alone would silently drop. No simulator
  /// reliably has such a calendar, hence the pure overload.
  func testRefusesAnImmutableCalendarEvenWhenItAllowsContentModifications() {
    let refusal = CalendarService.readOnlyRefusal(
      isImmutable: true,
      allowsContentModifications: true,
      title: "Work")

    XCTAssertEqual(refusal?.code, PlatformExceptionCodes.readOnly)
  }
}
