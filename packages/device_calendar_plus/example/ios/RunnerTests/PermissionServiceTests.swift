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
  private typealias Access = PermissionService.EffectiveAccess

  /// Stands in for EventKit: reports whatever status and capabilities the test
  /// case is holding, answers the request however the test case wants, and
  /// records every prompt so a test can assert the user was (or was not) asked.
  private struct StubAuthorization: CalendarAuthorization {
    let writeOnlyTier: () -> Bool
    let currentStatus: () -> OSAuthorization
    let grants: () -> Bool
    let recordRequest: (CalendarPermissionType) -> Void

    var supportsWriteOnly: Bool { writeOnlyTier() }
    var status: OSAuthorization { currentStatus() }

    func request(_ tier: CalendarPermissionType, completion: @escaping (Bool) -> Void) {
      recordRequest(tier)
      completion(grants())
    }
  }

  /// What `EKEventStore.authorizationStatus(for:)` reports, normalised. Starts
  /// as the first-launch value and stays there to model the stale window.
  private var status: OSAuthorization = .notDetermined
  /// Whether the OS has the iOS 17+ write-only tier. Defaults to the modern
  /// world; the iOS 13-16 tests flip it.
  private var supportsWriteOnly = true
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

  /// Each service gets its own `GrantRecord`, so a grant recorded in one test
  /// can never leak into the next.
  private func makeService() -> PermissionService {
    PermissionService(
      authorization: StubAuthorization(
        writeOnlyTier: { self.supportsWriteOnly },
        currentStatus: { self.status },
        grants: { self.requestSucceeds },
        recordRequest: { self.requestedTiers.append($0) }
      ),
      grantRecord: GrantRecord()
    )
  }

  /// Drives the real request path so the service records the grant the way a
  /// user tapping "Allow" would.
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

  /// The raw values cross the method channel and Dart's
  /// `CalendarPermissionStatus` parses them by name, degrading anything it does
  /// not recognise to `denied` without an exception — so a rename would surface
  /// as a mystery permission failure in the field rather than a red test.
  /// Pinned to literals here; every other assertion stays symbolic.
  func testEffectiveAccessRawValuesAreTheWireFormatDartParses() {
    XCTAssertEqual(
      [Access.full, .writeOnly, .denied, .restricted, .notDetermined].map(\.rawValue),
      ["granted", "writeOnly", "denied", "restricted", "notDetermined"])
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
    XCTAssertEqual(try requestPermissions(service), .denied)
    XCTAssertFalse(service.hasPermission(for: .write))
  }

  /// The other half of the refusal path: a refused *full* upgrade must report
  /// the tier the caller actually still holds, not "denied" and not
  /// "notDetermined" — the OS status is stale, so only the record knows.
  func testRequestPermissionsReportsWriteOnlyWhenAFullUpgradeIsRefusedWhileStale() throws {
    let service = makeService()
    try requestPermissions(service, writeOnly: true)

    requestSucceeds = false

    XCTAssertEqual(try requestPermissions(service), .writeOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// The reported bug: createEvent gates on `.write` and used to fail here.
  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service), .full)
    XCTAssertEqual(status, .notDetermined, "the stale status is the point of the test")
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
    XCTAssertEqual(try requestPermissions(service), .full)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  /// A Settings revocation surfaces as `.denied`, which must be honoured
  /// immediately — an earlier grant recorded in this process never masks it.
  func testHasPermissionIsFalseWhenAccessWasRevokedAfterAGrant() throws {
    let service = makeService()
    try requestPermissions(service)

    status = .denied

    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  func testHasPermissionFullIsFalseWhenTheOsReportsWriteOnlyAfterAFullGrant() throws {
    let service = makeService()
    try requestPermissions(service)

    // The OS is the authority once it answers: it granted only write-only.
    status = .writeOnly

    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  // MARK: - hasPermissions

  /// The ordinary post-restart state: the OS answers for itself and nothing is
  /// recorded, which is the path every launch after the first one takes.
  func testHasPermissionsReportsGrantedWhenTheOsReportsFullAccess() throws {
    status = .fullAccess
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), .full)
    XCTAssertTrue(service.hasPermission(for: .full))
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// The same, one tier down: a live write-only status still fails a `.full`
  /// gate without leaning on the recorded grant.
  func testHasPermissionsReportsWriteOnlyWhenTheOsReportsWriteOnly() throws {
    status = .writeOnly
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), .writeOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// The baseline the fix must preserve: Dart only fires its auto-request
  /// prompt when the status is exactly `notDetermined`, so an over-eager
  /// recorded-grant fallback would silently stop the app ever prompting.
  func testHasPermissionsReportsNotDeterminedWhenNothingWasEverGranted() throws {
    XCTAssertEqual(try makeService().hasPermissions().get(), .notDetermined)
  }

  /// The status query must agree with the gates, or a caller that checks
  /// before writing sees "notDetermined" while createEvent happily writes.
  func testHasPermissionsReportsGrantedWhileTheStatusIsStillStale() throws {
    let service = makeService()
    try requestPermissions(service)

    XCTAssertEqual(try service.hasPermissions().get(), .full)
  }

  func testHasPermissionsReportsWriteOnlyWhileTheStatusIsStillStale() throws {
    let service = makeService()
    try requestPermissions(service, writeOnly: true)

    XCTAssertEqual(try service.hasPermissions().get(), .writeOnly)
  }

  func testHasPermissionsReportsDeniedAfterAccessWasRevoked() throws {
    let service = makeService()
    try requestPermissions(service)

    status = .denied

    XCTAssertEqual(try service.hasPermissions().get(), .denied)
  }

  /// Restricted (parental controls, MDM) is its own status all the way to Dart.
  func testHasPermissionsReportsRestricted() throws {
    status = .restricted
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
    XCTAssertEqual(try requestPermissions(service), .full)

    XCTAssertEqual(try requestPermissions(service), .full)

    XCTAssertEqual(status, .notDetermined, "the stale status is the point of the test")
    XCTAssertEqual(requestedTiers, [.full], "the user must only be prompted once")
  }

  /// denied and restricted can only be changed in Settings, so firing a prompt
  /// would be a no-op the user still has to look at.
  func testRequestPermissionsReportsATerminalStatusWithoutPrompting() throws {
    for (osStatus, expected) in [
      (OSAuthorization.denied, Access.denied), (.restricted, Access.restricted),
    ] {
      status = osStatus
      requestedTiers = []
      let service = makeService()

      XCTAssertEqual(try requestPermissions(service), expected)
      XCTAssertEqual(requestedTiers, [], "\(expected) can only be changed in Settings")
    }
  }

  // MARK: - iOS 13-16, where the write-only tier does not exist

  /// `.authorized` there is full access, which the seam normalises to
  /// `.fullAccess` before the policy ever sees it.
  func testHasPermissionsReportsGrantedWhenALegacyOsReportsAuthorized() throws {
    supportsWriteOnly = false
    status = .fullAccess
    let service = makeService()

    XCTAssertEqual(try service.hasPermissions().get(), .full)
    XCTAssertTrue(service.hasPermission(for: .full))
  }

  /// #134's fix applies below iOS 17 too: the recorded grant covers the gate
  /// while the OS status is still `.notDetermined`.
  func testHasPermissionsReportsGrantedWhileStaleOnALegacyOs() throws {
    supportsWriteOnly = false
    let service = makeService()

    try requestPermissions(service)

    XCTAssertEqual(status, .notDetermined, "the stale status is the point of the test")
    XCTAssertEqual(try service.hasPermissions().get(), .full)
    XCTAssertTrue(service.hasPermission(for: .full))
  }

  /// The documented contract (`CalendarPermissionStatus`): asking for write-only
  /// where the tier does not exist prompts for — and reports — full access.
  func testRequestPermissionsAsksForFullAccessWhenALegacyOsHasNoWriteOnlyTier() throws {
    supportsWriteOnly = false
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service, writeOnly: true), .full)
    XCTAssertEqual(requestedTiers, [.full], "there is no write-only prompt to fire")
    XCTAssertTrue(service.hasPermission(for: .full))
  }
}
