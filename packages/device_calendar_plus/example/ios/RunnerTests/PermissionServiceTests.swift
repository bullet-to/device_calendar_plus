import XCTest

@testable import device_calendar_plus_ios

/// Regression coverage for #134: on iOS 17+ `EKEventStore.authorizationStatus`
/// can still report `.notDetermined` after the request handler has already
/// confirmed a grant, so the next call failed its permission gate ("Calendar
/// permission denied. Call requestPermissions() first.") until the app was
/// restarted.
///
/// Both OS-shaped facts are injected — the authorization seam (including
/// whether the OS has the iOS 17+ write-only tier) and the Info.plist usage
/// descriptions — so both sides of the version divide, and every configuration
/// error, are test fixtures rather than whatever the simulator happens to be
/// running and whatever the host app happens to declare.
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
    /// When set, the request fails instead of answering — EventKit handed back
    /// an error, or an interruption tore the system alert down.
    var requestError: Error?
    /// One entry per OS prompt fired — "did we ask the user" is the behaviour.
    private(set) var requestedTiers: [CalendarPermissionType] = []

    func request(
      _ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void
    ) {
      requestedTiers.append(tier)
      if let requestError = requestError {
        completion(.failure(requestError))
      } else {
        completion(.success(grants))
      }
    }
  }

  private struct StubError: Error {}

  /// A fully configured host app: every calendar key declared, non-empty.
  private static let allUsageDescriptions = [
    "NSCalendarsUsageDescription": "legacy",
    "NSCalendarsFullAccessUsageDescription": "full",
    "NSCalendarsWriteOnlyAccessUsageDescription": "write-only",
  ]

  private var authorization = StubAuthorization()
  /// What the host app declares in its Info.plist — injected, so the
  /// configuration-error tests can take keys away without touching a bundle.
  private var usageDescriptions = PermissionServiceTests.allUsageDescriptions

  override func setUp() {
    super.setUp()
    authorization = StubAuthorization()
    usageDescriptions = PermissionServiceTests.allUsageDescriptions
  }

  /// Each service gets its own `AccessRecord`, so an answer recorded in one
  /// test can never leak into the next. The record sits behind the seam in
  /// production too, so this is the real wiring with `.shared` swapped out.
  private func makeService() -> PermissionService {
    PermissionService(
      authorization: RecordingAuthorization(wrapping: authorization, record: AccessRecord()),
      usageDescriptions: { self.usageDescriptions[$0] })
  }

  /// Drives the real request path so the service records the answer the way a
  /// user tapping "Allow" (or "Don't Allow") would.
  @discardableResult
  private func requestPermissions(
    _ service: PermissionService,
    writeOnly: Bool = false
  ) throws -> Access {
    try requestPermissionsResult(service, writeOnly: writeOnly).get()
  }

  private func requestPermissionsResult(
    _ service: PermissionService,
    writeOnly: Bool = false
  ) throws -> Result<Access, PermissionError> {
    var reported: Result<Access, PermissionError>?
    let completed = expectation(description: "requestPermissions completed")
    service.requestPermissions(writeOnly: writeOnly) { result in
      reported = result
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
    return try XCTUnwrap(reported)
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

    XCTAssertEqual(
      authorization.requestedTiers, [.write, .full],
      "a full ask must still prompt while only write-only is held")
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

  /// The ordinary post-restart state, one row per OS status: the OS answers for
  /// itself, nothing is recorded, and the status query and the gates must agree
  /// — a caller that checks before writing must not see "notDetermined" while
  /// createEvent happily writes. `.notDetermined` is load-bearing in its own
  /// right: Dart only fires its auto-request prompt on exactly that value, so
  /// an over-eager fallback would silently stop the app ever prompting.
  func testHasPermissionsAndTheGatesAgreeOnEveryLiveOsStatus() throws {
    for (osStatus, satisfiesWrite, satisfiesFull) in [
      (Access.fullAccess, true, true),
      (.writeOnly, true, false),
      (.denied, false, false),
      // Restricted (parental controls, MDM) is its own status all the way to Dart.
      (.restricted, false, false),
      (.notDetermined, false, false),
    ] {
      authorization = StubAuthorization()
      authorization.status = osStatus
      let service = makeService()

      XCTAssertEqual(try service.hasPermissions().get(), osStatus)
      XCTAssertEqual(service.hasPermission(for: .write), satisfiesWrite, "\(osStatus) for .write")
      XCTAssertEqual(service.hasPermission(for: .full), satisfiesFull, "\(osStatus) for .full")
    }
  }

  /// The status query must agree with the gates inside the stale window too,
  /// where only the recorded answer knows what is held.
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

  /// A status check fires no prompt, so any one calendar key satisfies its
  /// configuration guard — an add-only app declaring only the write-only key
  /// can still read its status.
  func testHasPermissionsAcceptsAnySingleDeclaredUsageDescription() throws {
    for key in [
      "NSCalendarsUsageDescription",
      "NSCalendarsFullAccessUsageDescription",
      "NSCalendarsWriteOnlyAccessUsageDescription",
    ] {
      usageDescriptions = [key: "declared"]

      XCTAssertEqual(try makeService().hasPermissions().get(), .notDetermined, "declaring \(key)")
    }
  }

  /// An empty string is a declaration in name only — the OS shows a blank
  /// prompt — so it must fail the guard exactly like a missing key.
  func testHasPermissionsFailsWhenNoUsageDescriptionIsDeclared() {
    let nothingUseful: [[String: String]] = [[:], ["NSCalendarsUsageDescription": ""]]
    for declared in nothingUseful {
      usageDescriptions = declared

      guard case .failure(let error) = makeService().hasPermissions() else {
        XCTFail("expected a configuration failure for \(declared)")
        return
      }
      XCTAssertEqual(error.code, PlatformExceptionCodes.permissionsNotDeclared)
      // Every key, so following the advice once also satisfies the later request.
      for key in [
        "NSCalendarsFullAccessUsageDescription",
        "NSCalendarsWriteOnlyAccessUsageDescription",
        "NSCalendarsUsageDescription",
      ] {
        XCTAssertTrue(error.message.contains(key), "the fix-it must name \(key)")
      }
    }
  }

  // MARK: - requestPermissions

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

  /// A request that never got an answer — EventKit errored, or an incoming call
  /// tore the alert down — is not a refusal. Remembering it as one would leave
  /// the OS status `.notDetermined` forever with a terminal record in front of
  /// it, so the app could never prompt again short of a restart.
  func testRequestPermissionsStaysAskableAfterAFailedRequest() throws {
    authorization.requestError = StubError()
    let service = makeService()

    XCTAssertEqual(try requestPermissions(service), .notDetermined)
    XCTAssertEqual(try service.hasPermissions().get(), .notDetermined)

    authorization.requestError = nil

    XCTAssertEqual(try requestPermissions(service), .fullAccess)
    XCTAssertEqual(
      authorization.requestedTiers, [.full, .full], "a failed request must stay re-askable")
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

  // MARK: - requestPermissions usage-description guard

  /// Each iOS 17+ request variant demands its own key, and the OS raises rather
  /// than prompting without it, so the tier the ask resolved to decides which
  /// key is checked and which fix-it the developer is handed.
  func testRequestPermissionsFailsWhenTheTiersOwnUsageDescriptionIsMissing() throws {
    for (writeOnly, missingKey) in [
      (true, "NSCalendarsWriteOnlyAccessUsageDescription"),
      (false, "NSCalendarsFullAccessUsageDescription"),
    ] {
      authorization = StubAuthorization()
      usageDescriptions.removeValue(forKey: missingKey)
      let service = makeService()

      guard case .failure(let error) = try requestPermissionsResult(service, writeOnly: writeOnly)
      else {
        XCTFail("expected a configuration failure without \(missingKey)")
        return
      }
      XCTAssertEqual(error.code, PlatformExceptionCodes.permissionsNotDeclared)
      XCTAssertTrue(error.message.contains(missingKey), "the fix-it must name \(missingKey)")
      XCTAssertEqual(authorization.requestedTiers, [], "the OS would raise rather than prompt")

      usageDescriptions[missingKey] = "declared"
    }
  }

  /// An already-answered ask never fires a request, so it must report the
  /// status it holds rather than a configuration error for a key it will
  /// never need — an add-only app that ships without the full-access key still
  /// gets its write-only grant back.
  func testRequestPermissionsReportsATerminalStatusEvenWithoutTheUsageDescription() throws {
    usageDescriptions = [:]
    authorization.status = .denied

    XCTAssertEqual(try requestPermissions(makeService()), .denied)
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

  /// The tier keys do not exist before iOS 17, so a legacy OS must check — and
  /// name — only the legacy key, or every request on iOS 13-16 fails a guard
  /// for a key Apple never asked for.
  func testRequestPermissionsChecksOnlyTheLegacyKeyOnALegacyOs() throws {
    authorization.supportsWriteOnly = false
    usageDescriptions = ["NSCalendarsUsageDescription": "legacy"]

    XCTAssertEqual(try requestPermissions(makeService(), writeOnly: true), .fullAccess)

    authorization = StubAuthorization()
    authorization.supportsWriteOnly = false
    usageDescriptions = [
      "NSCalendarsFullAccessUsageDescription": "full",
      "NSCalendarsWriteOnlyAccessUsageDescription": "write-only",
    ]

    guard case .failure(let error) = try requestPermissionsResult(makeService()) else {
      return XCTFail("expected a configuration failure without the legacy key")
    }
    XCTAssertTrue(error.message.contains("NSCalendarsUsageDescription"))
  }
}
