import XCTest

@testable import device_calendar_plus_ios

/// Regression coverage for #134: on iOS 17+ `EKEventStore.authorizationStatus`
/// can still report `.notDetermined` after the request handler has already
/// confirmed a grant, so the next call failed its permission gate ("Calendar
/// permission denied. Call requestPermissions() first.") until the app was
/// restarted.
///
/// The whole OS authorization seam is injected, including whether the OS has
/// the iOS 17+ write-only tier, so both sides of the version divide are test
/// fixtures rather than whatever the simulator happens to be running.
final class PermissionServiceTests: XCTestCase {
  private typealias Access = CalendarAccess

  /// Stands in for EventKit: reports whatever status and capabilities the test
  /// set on it, answers the request the way the test wants, and records every
  /// prompt so a test can assert the user was (or was not) asked.
  private final class StubAuthorization: CalendarAuthorization {
    /// What `EKEventStore.authorizationStatus(for:)` reports, normalised.
    /// Starts as the first-launch value and stays there — the point of most of
    /// these tests is that nothing else moves it, so the stale window persists.
    var status: Access = .notDetermined
    /// Whether the OS has the iOS 17+ write-only tier. Defaults to the modern
    /// world; the iOS 13-16 test flips it.
    var supportsWriteOnly = true
    /// What the OS request handler reports back.
    var grants = true
    /// One entry per OS prompt fired — "did we ask the user" is the behaviour.
    private(set) var requestedTiers: [CalendarPermissionType] = []

    func request(_ tier: CalendarPermissionType, completion: @escaping (Bool) -> Void) {
      requestedTiers.append(tier)
      completion(grants)
    }
  }

  private var authorization = StubAuthorization()

  override func setUp() {
    super.setUp()
    authorization = StubAuthorization()
    // `hasPermissions` and `requestPermissions` read Bundle.main for the usage
    // descriptions, and RunnerTests is app-hosted, so these tests depend on the
    // example app's Info.plist. Assert it up front — otherwise removing a key
    // there fails tests in another package with no hint as to why. Matches the
    // production check: a key declared as an empty string does not count.
    for key in [
      "NSCalendarsUsageDescription",
      "NSCalendarsFullAccessUsageDescription",
      "NSCalendarsWriteOnlyAccessUsageDescription",
    ] {
      XCTAssertFalse(
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").isEmpty,
        "the RunnerTests host app must declare a non-empty \(key) in its Info.plist")
    }
  }

  /// Each service gets its own `AccessRecord`, so an answer recorded in one
  /// test can never leak into the next.
  private func makeService() -> PermissionService {
    PermissionService(authorization: authorization, accessRecord: AccessRecord())
  }

  /// Drives the real request path so the service records the answer the way a
  /// user tapping "Allow" (or "Don't Allow") would.
  @discardableResult
  private func requestPermissions(
    _ service: PermissionService,
    writeOnly: Bool = false
  ) throws -> Access {
    var reported: Result<Access, PermissionError>?
    let completed = expectation(description: "requestPermissions completed")
    service.requestPermissions(writeOnly: writeOnly) { result in
      reported = result
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
    return try XCTUnwrap(reported).get()
  }

  // MARK: - the wire format

  /// The wire values cross the method channel and Dart's
  /// `CalendarPermissionStatus` parses them by name, degrading anything it does
  /// not recognise to `denied` without an exception — so a rename would surface
  /// as a mystery permission failure in the field rather than a red test.
  /// Pinned to literals here; every other assertion stays symbolic.
  func testWireValuesAreTheStringsDartParses() {
    XCTAssertEqual(
      [Access.fullAccess, .writeOnly, .denied, .restricted, .notDetermined].map(\.wireValue),
      ["granted", "writeOnly", "denied", "restricted", "notDetermined"])
  }

  // MARK: - hasPermission

  func testHasPermissionWriteIsFalseWhenNothingWasEverGranted() {
    XCTAssertFalse(makeService().hasPermission(for: .write))
  }

  func testHasPermissionWriteIsFalseWhenTheUserRefusedTheRequest() throws {
    authorization.grants = false
    let service = makeService()

    // The OS status is still stale (`.notDetermined`) at this point, but the
    // handler just told us the user said no, so the refusal is reported as
    // denied rather than "we never asked" — by the gates and the status query
    // alike, or an app that renders off one and writes through the other sees
    // two different worlds.
    XCTAssertEqual(try requestPermissions(service), .denied)
    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertEqual(try service.hasPermissions().get(), .denied)
  }

  /// The other half of the refusal path: a refused *full* upgrade must report
  /// the tier the caller actually still holds, not "denied" and not
  /// "notDetermined" — the OS status is stale, so only the record knows.
  func testRequestPermissionsReportsWriteOnlyWhenAFullUpgradeIsRefusedWhileStale() throws {
    let service = makeService()
    try requestPermissions(service, writeOnly: true)

    authorization.grants = false

    XCTAssertEqual(try requestPermissions(service), .writeOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// The reported bug: createEvent gates on `.write` and used to fail here.
  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service), .fullAccess)
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  func testHasPermissionFullIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let service = makeService()

    try requestPermissions(service)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAWriteOnlyGrant() throws {
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service, writeOnly: true), .writeOnly)
    XCTAssertEqual(
      authorization.requestedTiers, [.write], "a write-only ask fires the write-only prompt")
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// A recorded write-only grant must not satisfy a full-access gate — the
  /// fallback keeps the tier distinction the live status would have made.
  func testHasPermissionFullIsFalseAfterAWriteOnlyGrant() throws {
    let service = makeService()

    try requestPermissions(service, writeOnly: true)

    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// An add-only app that later escalates to full access, all inside the stale
  /// window: the record must upgrade, or reads stay locked out until restart.
  func testHasPermissionFullIsTrueWhenAWriteOnlyGrantIsUpgradedToFullWhileStale() throws {
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service, writeOnly: true), .writeOnly)
    XCTAssertEqual(try requestPermissions(service), .fullAccess)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  /// A Settings revocation surfaces as `.denied`, which must be honoured
  /// immediately — an earlier grant recorded in this process never masks it.
  func testHasPermissionIsFalseWhenAccessWasRevokedAfterAGrant() throws {
    let service = makeService()
    try requestPermissions(service)

    authorization.status = .denied

    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  func testHasPermissionFullIsFalseWhenTheOsReportsWriteOnlyAfterAFullGrant() throws {
    let service = makeService()
    try requestPermissions(service)

    // The OS is the authority once it answers: it granted only write-only.
    authorization.status = .writeOnly

    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  // MARK: - hasPermissions

  /// The ordinary post-restart state: the OS answers for itself and nothing is
  /// recorded, which is the path every launch after the first one takes.
  func testHasPermissionsReportsGrantedWhenTheOsReportsFullAccess() throws {
    authorization.status = .fullAccess
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), .fullAccess)
    XCTAssertTrue(service.hasPermission(for: .full))
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// The same, one tier down: a live write-only status still fails a `.full`
  /// gate without leaning on the recorded grant.
  func testHasPermissionsReportsWriteOnlyWhenTheOsReportsWriteOnly() throws {
    authorization.status = .writeOnly
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), .writeOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// The baseline the fix must preserve: Dart only fires its auto-request
  /// prompt when the status is exactly `notDetermined`, so an over-eager
  /// recorded-answer fallback would silently stop the app ever prompting.
  func testHasPermissionsReportsNotDeterminedWhenNothingWasEverGranted() throws {
    XCTAssertEqual(try makeService().hasPermissions().get(), .notDetermined)
  }

  /// The status query must agree with the gates, or a caller that checks
  /// before writing sees "notDetermined" while createEvent happily writes.
  func testHasPermissionsReportsGrantedWhileTheStatusIsStillStale() throws {
    let service = makeService()
    try requestPermissions(service)

    XCTAssertEqual(try service.hasPermissions().get(), .fullAccess)
  }

  func testHasPermissionsReportsWriteOnlyWhileTheStatusIsStillStale() throws {
    let service = makeService()
    try requestPermissions(service, writeOnly: true)

    XCTAssertEqual(try service.hasPermissions().get(), .writeOnly)
  }

  func testHasPermissionsReportsDeniedAfterAccessWasRevoked() throws {
    let service = makeService()
    try requestPermissions(service)

    authorization.status = .denied

    XCTAssertEqual(try service.hasPermissions().get(), .denied)
  }

  /// Restricted (parental controls, MDM) is its own status all the way to Dart.
  func testHasPermissionsReportsRestricted() throws {
    authorization.status = .restricted
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), .restricted)
    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  // MARK: - requestPermissions

  /// The stale-window fix must not cost the user a second system prompt: the
  /// recorded grant satisfies the repeat ask, so no request reaches the OS.
  func testRequestPermissionsDoesNotPromptAgainWhileTheStatusIsStillStaleAfterAGrant() throws {
    let service = makeService()
    XCTAssertEqual(try requestPermissions(service), .fullAccess)

    XCTAssertEqual(try requestPermissions(service), .fullAccess)

    XCTAssertEqual(authorization.requestedTiers, [.full], "the user must only be prompted once")
  }

  /// A refusal is just as unaskable as a Settings denial: iOS never re-shows a
  /// prompt the user declined, so the recorded refusal must stop the second ask
  /// reaching the OS rather than firing a dialog that can never appear.
  func testRequestPermissionsDoesNotPromptAgainAfterARefusalWhileTheStatusIsStillStale() throws {
    authorization.grants = false
    let service = makeService()
    XCTAssertEqual(try requestPermissions(service), .denied)

    XCTAssertEqual(try requestPermissions(service), .denied)

    XCTAssertEqual(authorization.requestedTiers, [.full], "the user already said no")
  }

  /// denied and restricted can only be changed in Settings, so firing a prompt
  /// would be a no-op the user still has to look at.
  func testRequestPermissionsReportsATerminalStatusWithoutPrompting() throws {
    for (osStatus, expected) in [
      (Access.denied, Access.denied), (.restricted, .restricted),
    ] {
      authorization = StubAuthorization()
      authorization.status = osStatus
      let service = makeService()

      XCTAssertEqual(try requestPermissions(service), expected)
      XCTAssertEqual(authorization.requestedTiers, [], "\(expected) can only be changed in Settings")
    }
  }

  // MARK: - asking where the write-only tier does not exist

  /// The documented contract (`CalendarPermissionStatus`): asking for write-only
  /// where the tier does not exist (iOS 13-16) prompts for — and reports — full
  /// access.
  func testRequestPermissionsAsksForFullAccessWhenALegacyOsHasNoWriteOnlyTier() throws {
    authorization.supportsWriteOnly = false
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service, writeOnly: true), .fullAccess)
    XCTAssertEqual(authorization.requestedTiers, [.full], "there is no write-only prompt to fire")
    XCTAssertTrue(service.hasPermission(for: .full))
  }
}
