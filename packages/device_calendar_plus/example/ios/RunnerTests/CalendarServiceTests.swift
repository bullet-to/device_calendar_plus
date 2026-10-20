import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// Pure decision logic in `CalendarService` that no simulator can reach.
final class CalendarServiceTests: XCTestCase {

  // MARK: - readOnlyRefusal(isImmutable:allowsContentModifications:title:)

  // `CalendarService.readOnlyRefusal` is the iOS half of #126: the guard that
  // turns a rename or delete of a calendar EventKit won't touch into `readOnly`
  // instead of the `operationFailed` a thrown save becomes. It ORs two EventKit
  // flags. Three cells of that table read off the page; the fourth — immutable
  // yet `allowsContentModifications` — is the documented superset over
  // `Calendar.readOnly`, and nothing on a device can reach it: Dart never sees
  // `isImmutable`, so the on-device read-only-calendar test only ever picks
  // `!allowsContentModifications`. That one cell is pinned here through the
  // pure overload.

  /// EventKit says the calendar itself can't be edited or deleted even though
  /// events can still be added, so `listCalendars` calls it writable and the
  /// mutations still refuse it. This is the contract `doc/calendars.md`
  /// describes.
  func testRefusesAnImmutableCalendarEvenWhenItAllowsContentModifications() {
    XCTAssertEqual(
      CalendarService.readOnlyRefusal(
        isImmutable: true, allowsContentModifications: true, title: "Work")?.code,
      PlatformExceptionCodes.readOnly)
  }

  // MARK: - sourceSupportsCreation(sourceType:title:)

  // #233: title cases no simulator can reach; rationale on
  // `CalendarService.sourceSupportsCreation`.

  private func supports(_ type: EKSourceType, _ title: String) -> Bool {
    CalendarService.sourceSupportsCreation(sourceType: type, title: title)
  }

  func testSupportsCreationOnCalDavSourceTitledICloud() {
    XCTAssertTrue(supports(.calDAV, "iCloud"))
  }

  func testSupportsCreationOnCalDavSourceTitledICloudWithSurroundingWhitespace() {
    XCTAssertTrue(supports(.calDAV, " iCloud "))
  }

  func testSupportsCreationOnCalDavSourceTitledWithAMeDotComAppleId() {
    XCTAssertTrue(supports(.calDAV, "user@me.com"))
  }

  func testSupportsCreationOnCalDavSourceTitledWithAnICloudDotComAppleIdInAnyCase() {
    XCTAssertTrue(supports(.calDAV, "USER@iCloud.com"))
  }

  func testSupportsCreationOnCalDavSourceTitledWithAMacDotComAppleId() {
    XCTAssertTrue(supports(.calDAV, "x@mac.com"))
  }

  func testDoesNotSupportCreationOnGoogleCalDavSource() {
    XCTAssertFalse(supports(.calDAV, "user@gmail.com"))
  }

  func testDoesNotSupportCreationOnCalDavSourceWhoseTitleOnlyContainsAnAppleDomain() {
    XCTAssertFalse(supports(.calDAV, "user@me.com.example.org"))
  }

  func testSupportsCreationOnLocalSource() {
    XCTAssertTrue(supports(.local, "Default"))
  }

  func testDoesNotSupportCreationOnExchangeSource() {
    XCTAssertFalse(supports(.exchange, "user@icloud.com"))
  }
}
