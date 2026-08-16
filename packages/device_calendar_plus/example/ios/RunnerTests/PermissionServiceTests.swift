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
  /// built it with, answers the request the way the test wants, and records
  /// every prompt so a test can assert the user was (or was not) asked.
  private final class StubAuthorization: CalendarAuthorization {
    /// What `EKEventStore.authorizationStatus(for:)` reports, normalised.
    /// Starts as the first-launch value and stays there unless a test moves it
    /// — the point of most of these tests is that nothing else does, so the
    /// stale window persists.
    var status: Access
    /// Whether the OS has the iOS 17+ write-only tier. Defaults to the modern
    /// world; the iOS 13-16 tests ask for the legacy one.
    let supportsWriteOnly: Bool
    /// What the OS request handler reports back. Read at request time, so a
    /// test can change its mind between asks.
    var grants = true
    /// When set, the request fails instead of answering — EventKit handed back
    /// an error, or an interruption tore the system alert down.
    var requestError: Error?
    /// One entry per OS prompt fired — "did we ask the user" is the behaviour.
    private(set) var requestedTiers: [CalendarPermissionType] = []

    init(status: Access = .notDetermined, supportsWriteOnly: Bool = true) {
      self.status = status
      self.supportsWriteOnly = supportsWriteOnly
    }

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

  /// Builds a service and the stub behind it, both fresh. Everything a case
  /// needs to arrange is a parameter, so each test — and each row of a
  /// table-driven one — states its whole world in the call and nothing depends
  /// on the order two fixtures were touched in.
  ///
  /// Each service gets its own `AccessRecord` by default, so a grant recorded
  /// in one test can never leak into the next. The record sits behind the seam
  /// in production too, so this is the real wiring with `.shared` swapped out —
  /// the cross-engine test hands two services one record to stand in for it.
  private func makeService(
    status: Access = .notDetermined,
    supportsWriteOnly: Bool = true,
    usageDescriptions: [String: String] = PermissionServiceTests.allUsageDescriptions,
    record: AccessRecord = AccessRecord()
  ) -> (PermissionService, StubAuthorization) {
    let authorization = StubAuthorization(status: status, supportsWriteOnly: supportsWriteOnly)
    let service = makeService(
      authorization, usageDescriptions: usageDescriptions, record: record)
    return (service, authorization)
  }

  private func makeService(
    _ authorization: StubAuthorization,
    usageDescriptions: [String: String] = PermissionServiceTests.allUsageDescriptions,
    record: AccessRecord = AccessRecord()
  ) -> PermissionService {
    PermissionService(
      authorization: RecordingAuthorization(wrapping: authorization, record: record),
      usageDescriptions: { usageDescriptions[$0] })
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

  // MARK: - hasPermission

  func testHasPermissionWriteIsFalseWhenTheRequestWasNotGranted() throws {
    let (service, authorization) = makeService()
    authorization.grants = false

    // The OS status is still stale (`.notDetermined`) here, and an ungranted
    // request is not evidence of a refusal — see
    // `testAFullAskAnsweredAddEventsOnlyIsNotRecordedAsADenial` — so nothing is
    // recorded and the honest answer is the OS's own: no access yet, still
    // askable. The gates and the status query agree on it, or an app that
    // renders off one and writes through the other sees two different worlds.
    XCTAssertEqual(try requestPermissions(service), .notDetermined)
    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertEqual(try service.hasPermissions().get(), .notDetermined)
  }

  /// The reported bug: createEvent gates on `.write` and used to fail here.
  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let (service, _) = makeService()

    XCTAssertEqual(try requestPermissions(service), .fullAccess)
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  func testHasPermissionFullIsTrueWhileTheStatusIsStillStaleAfterAFullGrant() throws {
    let (service, _) = makeService()

    try requestPermissions(service)

    XCTAssertTrue(service.hasPermission(for: .full))
  }

  func testHasPermissionWriteIsTrueWhileTheStatusIsStillStaleAfterAWriteOnlyGrant() throws {
    let (service, authorization) = makeService()

    XCTAssertEqual(try requestPermissions(service, writeOnly: true), .writeOnly)
    XCTAssertEqual(
      authorization.requestedTiers, [.write], "a write-only ask fires the write-only prompt")
    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// A recorded write-only grant must not satisfy a full-access gate — the
  /// fallback keeps the tier distinction the live status would have made.
  func testHasPermissionFullIsFalseAfterAWriteOnlyGrant() throws {
    let (service, _) = makeService()

    try requestPermissions(service, writeOnly: true)

    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// An add-only app that later escalates to full access, all inside the stale
  /// window: the record must upgrade, or reads stay locked out until restart.
  func testHasPermissionFullIsTrueWhenAWriteOnlyGrantIsUpgradedToFullWhileStale() throws {
    let (service, authorization) = makeService()

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
    let (service, authorization) = makeService()
    try requestPermissions(service)

    authorization.status = .denied

    XCTAssertFalse(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  func testHasPermissionFullIsFalseWhenTheOsReportsWriteOnlyAfterAFullGrant() throws {
    let (service, authorization) = makeService()
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
      let (service, _) = makeService(status: osStatus)

      XCTAssertEqual(try service.hasPermissions().get(), osStatus)
      XCTAssertEqual(service.hasPermission(for: .write), satisfiesWrite, "\(osStatus) for .write")
      XCTAssertEqual(service.hasPermission(for: .full), satisfiesFull, "\(osStatus) for .full")
    }
  }

  /// The status query must agree with the gates inside the stale window too,
  /// where only the recorded grant knows what is held.
  func testHasPermissionsReportsGrantedWhileTheStatusIsStillStale() throws {
    let (service, _) = makeService()
    try requestPermissions(service)

    XCTAssertEqual(try service.hasPermissions().get(), .fullAccess)
  }

  func testHasPermissionsReportsWriteOnlyWhileTheStatusIsStillStale() throws {
    let (service, _) = makeService()
    try requestPermissions(service, writeOnly: true)

    XCTAssertEqual(try service.hasPermissions().get(), .writeOnly)
  }

  func testHasPermissionsReportsDeniedAfterAccessWasRevoked() throws {
    let (service, authorization) = makeService()
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
      let (service, _) = makeService(usageDescriptions: [key: "declared"])

      XCTAssertEqual(try service.hasPermissions().get(), .notDetermined, "declaring \(key)")
    }
  }

  /// An empty string is a declaration in name only — the OS shows a blank
  /// prompt — so it must fail the guard exactly like a missing key.
  func testHasPermissionsFailsWhenNoUsageDescriptionIsDeclared() {
    let nothingUseful: [[String: String]] = [[:], ["NSCalendarsUsageDescription": ""]]
    for declared in nothingUseful {
      let (service, _) = makeService(usageDescriptions: declared)

      guard case .failure(let error) = service.hasPermissions() else {
        XCTFail("expected a configuration failure for \(declared)")
        continue
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

  /// #135: `granted == false` does not mean the user refused everything — it
  /// means the app did not get *that tier*. On iOS 18 the full-access alert has
  /// a middle "Add Events Only" choice, which answers a `.full` ask that way
  /// while granting write-only. Recording it as `.denied` inside the stale
  /// window failed every write gate and stopped `requestPermissions` ever
  /// prompting again, for the rest of the process.
  func testAFullAskAnsweredAddEventsOnlyIsNotRecordedAsADenial() throws {
    let (service, authorization) = makeService()
    authorization.grants = false

    XCTAssertEqual(try requestPermissions(service), .notDetermined)
    // Dart auto-prompts on exactly `.notDetermined`, so this is the value that
    // keeps the app recoverable rather than locked out until a restart.
    XCTAssertEqual(try service.hasPermissions().get(), .notDetermined)

    // ...and once the live status catches up with what the OS actually granted,
    // the write gate opens on its own.
    authorization.status = .writeOnly

    XCTAssertTrue(service.hasPermission(for: .write))
  }

  /// The other half of that path: a full upgrade that was not granted must
  /// report the tier the caller still holds, not "denied" and not
  /// "notDetermined" — the OS status is stale, so only the record knows.
  func testRequestPermissionsReportsWriteOnlyWhenAFullUpgradeIsNotGrantedWhileStale() throws {
    let (service, authorization) = makeService()
    try requestPermissions(service, writeOnly: true)

    authorization.grants = false

    XCTAssertEqual(try requestPermissions(service), .writeOnly)
    XCTAssertTrue(service.hasPermission(for: .write))
    XCTAssertFalse(service.hasPermission(for: .full))
  }

  /// The stale-window fix must not cost the user a second system prompt: the
  /// recorded grant satisfies the repeat ask, so no request reaches the OS.
  func testRequestPermissionsDoesNotPromptAgainWhileTheStatusIsStillStaleAfterAGrant() throws {
    let (service, authorization) = makeService()
    XCTAssertEqual(try requestPermissions(service), .fullAccess)

    XCTAssertEqual(try requestPermissions(service), .fullAccess)

    XCTAssertEqual(authorization.requestedTiers, [.full], "the user must only be prompted once")
  }

  /// Only grants are remembered, so a second ask after an ungranted one goes
  /// back to the OS. That is the deliberate trade: at most one redundant round
  /// trip — EventKit answers an already-decided permission immediately, with no
  /// UI — against never mistaking "not that tier" for a permanent refusal.
  func testRequestPermissionsStaysAskableAfterAnUngrantedRequest() throws {
    let (service, authorization) = makeService()
    authorization.grants = false
    XCTAssertEqual(try requestPermissions(service), .notDetermined)

    XCTAssertEqual(try requestPermissions(service), .notDetermined)

    XCTAssertEqual(
      authorization.requestedTiers, [.full, .full], "an ungranted ask must stay re-askable")
  }

  /// A request that never got an answer — EventKit errored, or an incoming call
  /// tore the alert down — leaves the record alone just the same, so the app
  /// stays askable and a later grant still lands.
  func testRequestPermissionsStaysAskableAfterAFailedRequest() throws {
    let (service, authorization) = makeService()
    authorization.requestError = StubError()

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
      let (service, authorization) = makeService(status: osStatus)

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
      var declared = PermissionServiceTests.allUsageDescriptions
      declared.removeValue(forKey: missingKey)
      let (service, authorization) = makeService(usageDescriptions: declared)

      guard case .failure(let error) = try requestPermissionsResult(service, writeOnly: writeOnly)
      else {
        XCTFail("expected a configuration failure without \(missingKey)")
        continue
      }
      XCTAssertEqual(error.code, PlatformExceptionCodes.permissionsNotDeclared)
      XCTAssertTrue(error.message.contains(missingKey), "the fix-it must name \(missingKey)")
      XCTAssertEqual(authorization.requestedTiers, [], "the OS would raise rather than prompt")
    }
  }

  /// An already-answered ask never fires a request, so it must report the
  /// status it holds rather than a configuration error for a key it will
  /// never need — an add-only app that ships without the full-access key still
  /// gets its write-only grant back.
  func testRequestPermissionsReportsATerminalStatusEvenWithoutTheUsageDescription() throws {
    let (service, _) = makeService(status: .denied, usageDescriptions: [:])

    XCTAssertEqual(try requestPermissions(service), .denied)
  }

  // MARK: - asking where the write-only tier does not exist

  /// The documented contract (`CalendarPermissionStatus`): asking for write-only
  /// where the tier does not exist (iOS 13-16) prompts for — and reports — full
  /// access.
  func testRequestPermissionsAsksForFullAccessWhenALegacyOsHasNoWriteOnlyTier() throws {
    let (service, authorization) = makeService(supportsWriteOnly: false)

    XCTAssertEqual(try requestPermissions(service, writeOnly: true), .fullAccess)
    XCTAssertEqual(authorization.requestedTiers, [.full], "there is no write-only prompt to fire")
    XCTAssertTrue(service.hasPermission(for: .full))
  }

  /// The tier keys do not exist before iOS 17, so a legacy OS must check — and
  /// name — only the legacy key, or every request on iOS 13-16 fails a guard
  /// for a key Apple never asked for.
  func testRequestPermissionsChecksOnlyTheLegacyKeyOnALegacyOs() throws {
    let (withLegacyKey, _) = makeService(
      supportsWriteOnly: false,
      usageDescriptions: ["NSCalendarsUsageDescription": "legacy"])

    XCTAssertEqual(try requestPermissions(withLegacyKey, writeOnly: true), .fullAccess)

    let (withTierKeysOnly, _) = makeService(
      supportsWriteOnly: false,
      usageDescriptions: [
        "NSCalendarsFullAccessUsageDescription": "full",
        "NSCalendarsWriteOnlyAccessUsageDescription": "write-only",
      ])

    guard case .failure(let error) = try requestPermissionsResult(withTierKeysOnly) else {
      return XCTFail("expected a configuration failure without the legacy key")
    }
    XCTAssertTrue(error.message.contains("NSCalendarsUsageDescription"))
  }

  // MARK: - the shared access record

  /// The record is process-wide by design: a `FlutterEngineGroup` or add-to-app
  /// host builds one `PermissionService` per engine, and the answer the user
  /// gave belongs to the app rather than to whichever engine happened to ask.
  /// Both engines sit inside the stale window here — each one's OS status still
  /// reports `.notDetermined` — so only the shared record can carry the grant
  /// across, and without it the second engine would re-prompt for access the
  /// app already holds.
  func testAGrantThroughOneEngineIsHonouredByAnotherSharingTheRecord() throws {
    let record = AccessRecord()
    let askingStub = StubAuthorization()
    let otherStub = StubAuthorization()
    let asking = makeService(askingStub, record: record)
    let other = makeService(otherStub, record: record)

    XCTAssertEqual(try requestPermissions(asking), .fullAccess)

    XCTAssertEqual(otherStub.status, .notDetermined, "the other engine's OS status is still stale")
    XCTAssertTrue(other.hasPermission(for: .write))
    XCTAssertTrue(other.hasPermission(for: .full))
    XCTAssertEqual(try requestPermissions(other), .fullAccess)
    XCTAssertEqual(otherStub.requestedTiers, [], "the shared answer means no second prompt")
  }
}
