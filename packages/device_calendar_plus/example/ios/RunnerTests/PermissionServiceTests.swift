import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// Regression coverage for #134: on iOS 17+ `EKEventStore.authorizationStatus`
/// can still report `.notDetermined` after the request handler has already
/// confirmed a grant, so the next call failed its permission gate ("Calendar
/// permission denied. Call requestPermissions() first.") until the app was
/// restarted.
///
/// The authorization status and the OS request are injected so the whole
/// stale-status window can be reproduced without a real system prompt.
final class PermissionServiceTests: XCTestCase {
  /// What `EKEventStore.authorizationStatus(for:)` reports. Starts as the
  /// first-launch value and stays there to model the stale window.
  private var status: EKAuthorizationStatus = .notDetermined
  /// What the OS request handler reports back.
  private var requestSucceeds = true

  private func makeService() -> PermissionService {
    PermissionService(
      eventStore: EKEventStore(),
      authorizationStatus: { self.status },
      requestAccess: { _, completion in completion(self.requestSucceeds, nil) }
    )
  }

  /// Drives the real request path so the service records the grant the way a
  /// user tapping "Allow" would.
  private func requestPermissions(
    _ service: PermissionService,
    writeOnly: Bool = false
  ) -> String? {
    var reported: String?
    let completed = expectation(description: "requestPermissions completed")
    service.requestPermissions(writeOnly: writeOnly) { result in
      reported = try? result.get()
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
    return reported
  }

  // MARK: - hasPermission

  func testHasPermissionWriteIsFalseWhenNothingWasEverGranted() {
    XCTAssertFalse(makeService().hasPermission(for: .write))
  }

  func testHasPermissionWriteIsFalseWhenTheUserRefusedTheRequest() {
    requestSucceeds = false
    let service = makeService()

    XCTAssertEqual(requestPermissions(service), PermissionService.statusNotDetermined)
    XCTAssertFalse(service.hasPermission(for: .write))
  }

  /// The reported bug: createEvent gates on `.write` and used to fail here.
  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() {
    let service = makeService()

    XCTAssertEqual(requestPermissions(service), PermissionService.statusGranted)
    XCTAssertEqual(status, .notDetermined, "the stale status is the point of the test")
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  func testHasPermissionFullIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() {
    let service = makeService()

    _ = requestPermissions(service)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAWriteOnlyGrant() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()

    XCTAssertEqual(
      requestPermissions(service, writeOnly: true), PermissionService.statusWriteOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// A recorded write-only grant must not satisfy a full-access gate — the
  /// fallback keeps the tier distinction the live status would have made.
  func testHasPermissionFullIsFalseAfterAWriteOnlyGrant() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()

    _ = requestPermissions(service, writeOnly: true)

    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// A Settings revocation surfaces as `.denied`, which must be honoured
  /// immediately — an earlier grant recorded in this process never masks it.
  func testHasPermissionIsFalseWhenAccessWasRevokedAfterAGrant() {
    let service = makeService()
    _ = requestPermissions(service)

    status = .denied

    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  func testHasPermissionFullIsFalseWhenTheOsReportsWriteOnlyAfterAFullGrant() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()
    _ = requestPermissions(service)

    // The OS is the authority once it answers: it granted only write-only.
    status = .writeOnly

    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  // MARK: - hasPermissions

  /// The status query must agree with the gates, or a caller that checks
  /// before writing sees "notDetermined" while createEvent happily writes.
  func testHasPermissionsReportsGrantedWhileTheStatusIsStillStale() {
    let service = makeService()
    _ = requestPermissions(service)

    XCTAssertEqual(try? service.hasPermissions().get(), PermissionService.statusGranted)
  }

  func testHasPermissionsReportsWriteOnlyWhileTheStatusIsStillStale() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()
    _ = requestPermissions(service, writeOnly: true)

    XCTAssertEqual(try? service.hasPermissions().get(), PermissionService.statusWriteOnly)
  }

  func testHasPermissionsReportsDeniedAfterAccessWasRevoked() {
    let service = makeService()
    _ = requestPermissions(service)

    status = .denied

    XCTAssertEqual(try? service.hasPermissions().get(), PermissionService.statusDenied)
  }
}
