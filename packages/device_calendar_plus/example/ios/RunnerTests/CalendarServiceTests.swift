import XCTest

@testable import device_calendar_plus_ios

/// `CalendarService.readOnlyRefusal` is the iOS half of #126: the guard that
/// turns a rename or delete of a calendar EventKit won't touch into `readOnly`
/// instead of the `operationFailed` a thrown save becomes. It reads two
/// EventKit flags, and no simulator reliably has a calendar with either set,
/// so the truth table is pinned here through the pure overload. Mirrors the
/// Kotlin `CalendarServiceTest` shape: class, method, behaviour.
final class CalendarServiceTests: XCTestCase {

  // MARK: - readOnlyRefusal(isImmutable:allowsContentModifications:title:)

  private func refusal(isImmutable: Bool, allowsContentModifications: Bool) -> CalendarError? {
    return CalendarService.readOnlyRefusal(
      isImmutable: isImmutable,
      allowsContentModifications: allowsContentModifications,
      title: "Work")
  }

  /// The one cell that goes ahead: mutable, and events can be added.
  func testAcceptsAMutableCalendarThatAllowsContentModifications() {
    XCTAssertNil(refusal(isImmutable: false, allowsContentModifications: true))
  }

  /// The calendar `listCalendars` reports as `readOnly`.
  func testRefusesACalendarThatDisallowsContentModifications() {
    XCTAssertEqual(
      refusal(isImmutable: false, allowsContentModifications: false)?.code,
      PlatformExceptionCodes.readOnly)
  }

  /// The superset cell: EventKit says the calendar itself can't be edited or
  /// deleted even though events can still be added, so `listCalendars` calls
  /// it writable and the mutations still refuse it. This is the contract the
  /// `deleteCalendar` dartdoc describes.
  func testRefusesAnImmutableCalendarEvenWhenItAllowsContentModifications() {
    XCTAssertEqual(
      refusal(isImmutable: true, allowsContentModifications: true)?.code,
      PlatformExceptionCodes.readOnly)
  }

  func testRefusesAnImmutableCalendarThatDisallowsContentModifications() {
    XCTAssertEqual(
      refusal(isImmutable: true, allowsContentModifications: false)?.code,
      PlatformExceptionCodes.readOnly)
  }

  /// The message names the calendar, so a caller iterating several can tell
  /// which one was refused.
  func testRefusalNamesTheCalendar() {
    XCTAssertEqual(
      refusal(isImmutable: true, allowsContentModifications: true)?.message,
      "Calendar 'Work' is read-only and cannot be modified or deleted")
  }
}
