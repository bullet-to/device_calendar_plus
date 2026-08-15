import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// Regression coverage for #134: on iOS 17+ `EKEventStore.authorizationStatus`
/// can still report `.notDetermined` after the request handler has already
/// confirmed a grant, so the next call failed its permission gate ("Calendar
/// permission denied. Call requestPermissions() first.") until the app was
/// restarted.
///
/// The whole OS authorization seam is injected so the stale-status window can
/// be reproduced without a real system prompt.
final class PermissionServiceTests: XCTestCase {
  /// Stands in for EventKit: reports whatever status the test case is holding
  /// and answers the request however the test case wants.
  private struct StubAuthorization: CalendarAuthorization {
    let currentStatus: () -> EKAuthorizationStatus
    let grants: () -> Bool

    var status: EKAuthorizationStatus { currentStatus() }

    func request(
      writeOnly: Bool,
      completion: @escaping (Bool, CalendarPermissionType) -> Void
    ) {
      // Mirrors EventKitAuthorization: the write-only tier only exists on
      // iOS 17+, so anything older can only ever grant full access.
      let tier: CalendarPermissionType
      if #available(iOS 17.0, *) {
        tier = writeOnly ? .write : .full
      } else {
        tier = .full
      }
      completion(grants(), tier)
    }
  }

  /// What `EKEventStore.authorizationStatus(for:)` reports. Starts as the
  /// first-launch value and stays there to model the stale window.
  private var status: EKAuthorizationStatus = .notDetermined
  /// What the OS request handler reports back.
  private var requestSucceeds = true

  override func setUp() {
    super.setUp()
    // `hasPermissions` and `requestPermissions` read Bundle.main for the usage
    // descriptions, and RunnerTests is app-hosted, so these tests depend on the
    // example app's Info.plist. Assert it up front — otherwise removing a key
    // there fails tests in another package with no hint as to why.
    for key in [
      "NSCalendarsUsageDescription",
      "NSCalendarsFullAccessUsageDescription",
      "NSCalendarsWriteOnlyAccessUsageDescription",
    ] {
      XCTAssertNotNil(
        Bundle.main.object(forInfoDictionaryKey: key),
        "the RunnerTests host app must declare \(key) in its Info.plist")
    }
  }

  private func makeService() -> PermissionService {
    PermissionService(
      authorization: StubAuthorization(
        currentStatus: { self.status },
        grants: { self.requestSucceeds }
      )
    )
  }

  /// Drives the real request path so the service records the grant the way a
  /// user tapping "Allow" would.
  private func requestPermissions(
    _ service: PermissionService,
    writeOnly: Bool = false
  ) throws -> String {
    var reported: Result<String, PermissionError>?
    let completed = expectation(description: "requestPermissions completed")
    service.requestPermissions(writeOnly: writeOnly) { result in
      reported = result
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
    return try XCTUnwrap(reported).get()
  }

  // MARK: - hasPermission

  func testHasPermissionWriteIsFalseWhenNothingWasEverGranted() {
    XCTAssertFalse(makeService().hasPermission(for: .write))
  }

  func testHasPermissionWriteIsFalseWhenTheUserRefusedTheRequest() throws {
    requestSucceeds = false
    let service = makeService()

    // The OS status is still stale (`.notDetermined`) at this point, but the
    // handler just told us the user said no, so the refusal is reported as
    // denied rather than "we never asked".
    XCTAssertEqual(try requestPermissions(service), PermissionService.statusDenied)
    XCTAssertFalse(service.hasPermission(for: .write))
  }

  /// The reported bug: createEvent gates on `.write` and used to fail here.
  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service), PermissionService.statusGranted)
    XCTAssertEqual(status, .notDetermined, "the stale status is the point of the test")
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  func testHasPermissionFullIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let service = makeService()

    _ = try requestPermissions(service)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAWriteOnlyGrant() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()

    XCTAssertEqual(
      try requestPermissions(service, writeOnly: true), PermissionService.statusWriteOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// A recorded write-only grant must not satisfy a full-access gate — the
  /// fallback keeps the tier distinction the live status would have made.
  func testHasPermissionFullIsFalseAfterAWriteOnlyGrant() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()

    _ = try requestPermissions(service, writeOnly: true)

    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// An add-only app that later escalates to full access, all inside the stale
  /// window: the record must upgrade, or reads stay locked out until restart.
  func testHasPermissionFullIsTrueWhenAWriteOnlyGrantIsUpgradedToFullWhileStale() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()

    XCTAssertEqual(
      try requestPermissions(service, writeOnly: true), PermissionService.statusWriteOnly)
    XCTAssertEqual(try requestPermissions(service), PermissionService.statusGranted)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  /// A Settings revocation surfaces as `.denied`, which must be honoured
  /// immediately — an earlier grant recorded in this process never masks it.
  func testHasPermissionIsFalseWhenAccessWasRevokedAfterAGrant() throws {
    let service = makeService()
    _ = try requestPermissions(service)

    status = .denied

    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  func testHasPermissionFullIsFalseWhenTheOsReportsWriteOnlyAfterAFullGrant() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()
    _ = try requestPermissions(service)

    // The OS is the authority once it answers: it granted only write-only.
    status = .writeOnly

    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  // MARK: - hasPermissions

  /// The status query must agree with the gates, or a caller that checks
  /// before writing sees "notDetermined" while createEvent happily writes.
  func testHasPermissionsReportsGrantedWhileTheStatusIsStillStale() throws {
    let service = makeService()
    _ = try requestPermissions(service)

    XCTAssertEqual(try service.hasPermissions().get(), PermissionService.statusGranted)
  }

  func testHasPermissionsReportsWriteOnlyWhileTheStatusIsStillStale() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()
    _ = try requestPermissions(service, writeOnly: true)

    XCTAssertEqual(try service.hasPermissions().get(), PermissionService.statusWriteOnly)
  }

  func testHasPermissionsReportsDeniedAfterAccessWasRevoked() throws {
    let service = makeService()
    _ = try requestPermissions(service)

    status = .denied

    XCTAssertEqual(try service.hasPermissions().get(), PermissionService.statusDenied)
  }
}
