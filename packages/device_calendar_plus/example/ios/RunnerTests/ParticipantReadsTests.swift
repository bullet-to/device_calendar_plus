import XCTest

@testable import device_calendar_plus_ios

/// organizerMap's blank and `mailto:` handling, which the simulator suite
/// can't reach: EventKit only reports an organizer on an event with guests,
/// and the plugin can't add guests on iOS. Mirrors Android's
/// AttendeeReadsTest organizerOf cases.
final class ParticipantReadsTests: XCTestCase {
  private let mailto = URL(string: "mailto:owner@example.com")!

  // MARK: - organizerMap(name:url:)

  func testOrganizerMap_readsTheNameAndMailtoEmail() {
    XCTAssertEqual(
      organizerMap(name: "Owner", url: mailto),
      ["name": "Owner", "emailAddress": "owner@example.com"]
    )
  }

  func testOrganizerMap_leavesOutAMissingName() {
    XCTAssertEqual(
      organizerMap(name: nil, url: mailto),
      ["emailAddress": "owner@example.com"]
    )
  }

  func testOrganizerMap_leavesOutAWhitespaceOnlyName() {
    XCTAssertEqual(
      organizerMap(name: " \n", url: mailto),
      ["emailAddress": "owner@example.com"]
    )
  }

  func testOrganizerMap_leavesOutTheEmailForANonMailtoURL() {
    let url = URL(string: "https://example.com/principals/owner")!

    XCTAssertEqual(organizerMap(name: "Owner", url: url), ["name": "Owner"])
  }

  func testOrganizerMap_leavesOutABlankMailtoEmail() {
    let url = URL(string: "mailto:")!

    XCTAssertEqual(organizerMap(name: "Owner", url: url), ["name": "Owner"])
  }

  func testOrganizerMap_isNilWithNeitherANameNorAnEmail() {
    let url = URL(string: "https://example.com/principals/owner")!

    XCTAssertNil(organizerMap(name: " ", url: url))
    XCTAssertNil(organizerMap(name: nil, url: URL(string: "mailto:")!))
  }
}
