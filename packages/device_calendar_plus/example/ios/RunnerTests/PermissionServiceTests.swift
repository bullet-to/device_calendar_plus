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
  private typealias Access = PermissionService.EffectiveAccess

  /// Stands in for EventKit: reports whatever status the test case is holding,
  /// answers the request however the test case wants, and records every prompt
  /// so a test can assert the user was (or was not) asked.
  private struct StubAuthorization: CalendarAuthorization {
    let currentStatus: () -> EKAuthorizationStatus
    let grants: () -> Bool
    let recordRequest: (CalendarPermissionType) -> Void

    var status: EKAuthorizationStatus { currentStatus() }

    func request(_ tier: CalendarPermissionType, completion: @escaping (Bool) -> Void) {
      recordRequest(tier)
      completion(grants())
    }
  }

  /// What `EKEventStore.authorizationStatus(for:)` reports. Starts as the
  /// first-launch value and stays there to model the stale window.
  private var status: EKAuthorizationStatus = .notDetermined
  /// What the OS request handler reports back.
  private var requestSucceeds = true
  /// One entry per OS prompt fired — "did we ask the user" is the behaviour.
  private var requestedTiers: [CalendarPermissionType] = []

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
        grants: { self.requestSucceeds },
        recordRequest: { self.requestedTiers.append($0) }
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
    XCTAssertEqual(try requestPermissions(service), Access.denied.rawValue)
    XCTAssertFalse(service.hasPermission(for: .write))
  }

  /// The other half of the refusal path: a refused *full* upgrade must report
  /// the tier the caller actually still holds, not "denied" and not
  /// "notDetermined" — the OS status is stale, so only the record knows.
  func testRequestPermissionsReportsWriteOnlyWhenAFullUpgradeIsRefusedWhileStale() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()
    _ = try requestPermissions(service, writeOnly: true)

    requestSucceeds = false

    XCTAssertEqual(try requestPermissions(service), Access.writeOnly.rawValue)
    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// The reported bug: createEvent gates on `.write` and used to fail here.
  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service), Access.full.rawValue)
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
      try requestPermissions(service, writeOnly: true), Access.writeOnly.rawValue)
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
      try requestPermissions(service, writeOnly: true), Access.writeOnly.rawValue)
    XCTAssertEqual(try requestPermissions(service), Access.full.rawValue)

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

    XCTAssertEqual(try service.hasPermissions().get(), Access.full.rawValue)
  }

  func testHasPermissionsReportsWriteOnlyWhileTheStatusIsStillStale() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier only exists on iOS 17+")
    }
    let service = makeService()
    _ = try requestPermissions(service, writeOnly: true)

    XCTAssertEqual(try service.hasPermissions().get(), Access.writeOnly.rawValue)
  }

  func testHasPermissionsReportsDeniedAfterAccessWasRevoked() throws {
    let service = makeService()
    _ = try requestPermissions(service)

    status = .denied

    XCTAssertEqual(try service.hasPermissions().get(), Access.denied.rawValue)
  }

  /// Restricted (parental controls, MDM) is its own status all the way to Dart.
  func testHasPermissionsReportsRestricted() throws {
    status = .restricted
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), Access.restricted.rawValue)
    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  // MARK: - requestPermissions

  /// The stale-window fix must not cost the user a second system prompt: the
  /// recorded grant satisfies the repeat ask, so no request reaches the OS.
  func testRequestPermissionsDoesNotPromptAgainWhileTheStatusIsStillStaleAfterAGrant() throws {
    let service = makeService()
    XCTAssertEqual(try requestPermissions(service), Access.full.rawValue)

    XCTAssertEqual(try requestPermissions(service), Access.full.rawValue)

    XCTAssertEqual(status, .notDetermined, "the stale status is the point of the test")
    XCTAssertEqual(requestedTiers, [.full], "the user must only be prompted once")
  }

  /// denied and restricted can only be changed in Settings, so firing a prompt
  /// would be a no-op the user still has to look at.
  func testRequestPermissionsReportsATerminalStatusWithoutPrompting() throws {
    for (osStatus, expected) in [
      (EKAuthorizationStatus.denied, Access.denied), (.restricted, Access.restricted),
    ] {
      status = osStatus
      requestedTiers = []
      let service = makeService()

      XCTAssertEqual(try requestPermissions(service), expected.rawValue)
      XCTAssertEqual(requestedTiers, [], "\(expected) can only be changed in Settings")
    }
  }
}
