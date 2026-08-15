import EventKit
import Foundation

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

/// The OS-level calendar authorization seam.
///
/// Injected into `PermissionService` so tests can drive the whole grant path
/// without a real system prompt. The requester — not the service — knows which
/// tier it actually asked the OS for, so it reports that back alongside the
/// grant; that keeps the one `#available` branch that matters in a single place.
protocol CalendarAuthorization {
  var status: EKAuthorizationStatus { get }

  /// Fires the OS prompt and reports the tier actually requested, plus whether
  /// it was granted.
  func request(
    writeOnly: Bool,
    completion: @escaping (_ granted: Bool, _ tier: CalendarPermissionType) -> Void
  )
}

/// The production `CalendarAuthorization`, backed by EventKit.
struct EventKitAuthorization: CalendarAuthorization {
  let eventStore: EKEventStore

  var status: EKAuthorizationStatus {
    EKEventStore.authorizationStatus(for: .event)
  }

  func request(
    writeOnly: Bool,
    completion: @escaping (Bool, CalendarPermissionType) -> Void
  ) {
    if #available(iOS 17.0, *) {
      if writeOnly {
        eventStore.requestWriteOnlyAccessToEvents { granted, _ in completion(granted, .write) }
      } else {
        eventStore.requestFullAccessToEvents { granted, _ in completion(granted, .full) }
      }
    } else {
      // iOS 16 and below: only full access exists, so any grant is full access.
      eventStore.requestAccess(to: .event) { granted, _ in completion(granted, .full) }
    }
  }
}

class PermissionService {
  private let authorization: CalendarAuthorization

  /// The tier this process was granted, if any — see `recordGrant`. Read from
  /// the provider queue (the data endpoints) and from the main thread (the
  /// modal endpoints and the method-channel handlers), and written from
  /// whichever thread EventKit calls the request handler on, so every access
  /// goes through `grantLock`.
  private let grantLock = NSLock()
  private var recordedGrant: CalendarPermissionType?

  // Permission status values matching CalendarPermissionStatus enum
  static let statusGranted = "granted"
  static let statusWriteOnly = "writeOnly"
  static let statusDenied = "denied"
  static let statusRestricted = "restricted"
  static let statusNotDetermined = "notDetermined"

  init(authorization: CalendarAuthorization) {
    self.authorization = authorization
  }

  /// Remembers the tier the user just granted this process.
  ///
  /// On iOS 17+ `EKEventStore.authorizationStatus(for:)` can still report
  /// `.notDetermined` for a short while after the request handler has already
  /// confirmed a grant (#134), which made the very next call fail its
  /// permission gate until the app was restarted. The recorded tier is the
  /// fallback the `.notDetermined` branches consult.
  ///
  /// Nothing ever clears it, and nothing needs to. It is only consulted while
  /// the OS says `.notDetermined`, so any other status — a `.denied` from a
  /// Settings revocation, say — wins outright. `.notDetermined` *is* itself a
  /// status the OS can return to (Reset Location & Privacy, an MDM policy
  /// change), and the record would mask that; what saves us is that iOS
  /// terminates an app whose privacy settings change, so the record cannot
  /// outlive the grant it describes.
  private func recordGrant(_ type: CalendarPermissionType) {
    grantLock.lock()
    defer { grantLock.unlock() }
    // Belt and braces: only ever upgrade, so the record can never report less
    // access than the user granted this process. The downgrade it guards
    // against is unreachable in practice — `requestPermissions` early-returns
    // on an already-satisfied tier, so a recorded `.full` never reaches a
    // write-only request — but the upgrade half (write-only → full) is live.
    if recordedGrant == nil || type == .full {
      recordedGrant = type
    }
  }

  private func currentRecordedGrant() -> CalendarPermissionType? {
    grantLock.lock()
    defer { grantLock.unlock() }
    return recordedGrant
  }

  /// The access this process effectively holds. Every decision — the gates, the
  /// status reported to Dart, and whether a request is worth firing — is made
  /// on this, so they can never disagree. The wire-format strings appear only
  /// at the reply edge, via `statusString`.
  private enum EffectiveAccess {
    case full
    case writeOnly
    case denied
    case restricted
    /// Nothing granted and nothing recorded — we have not asked yet.
    case notDetermined

    init(granted type: CalendarPermissionType) {
      switch type {
      case .full:
        self = .full
      case .write:
        self = .writeOnly
      }
    }

    var statusString: String {
      switch self {
      case .full:
        return PermissionService.statusGranted
      case .writeOnly:
        return PermissionService.statusWriteOnly
      case .denied:
        return PermissionService.statusDenied
      case .restricted:
        return PermissionService.statusRestricted
      case .notDetermined:
        return PermissionService.statusNotDetermined
      }
    }
  }

  /// Resolves the OS status, falling back to the grant recorded in this process
  /// while — and only while — the OS still says `.notDetermined`. A real
  /// `.denied` (a Settings revocation, say) is honoured immediately and is
  /// never masked by an earlier grant.
  private func effectiveAccess() -> EffectiveAccess {
    let status = authorization.status

    if #available(iOS 17.0, *) {
      switch status {
      case .fullAccess:
        return .full
      case .writeOnly:
        return .writeOnly
      case .denied:
        return .denied
      case .restricted:
        return .restricted
      case .notDetermined:
        return recordedAccess()
      @unknown default:
        return .denied
      }
    } else {
      // iOS 16 and below only has .authorized, which is full access.
      switch status {
      case .authorized:
        return .full
      case .denied:
        return .denied
      case .restricted:
        return .restricted
      case .notDetermined:
        return recordedAccess()
      @unknown default:
        return .denied
      }
    }
  }

  private func recordedAccess() -> EffectiveAccess {
    currentRecordedGrant().map(EffectiveAccess.init(granted:)) ?? .notDetermined
  }

  /// Checks if calendar permissions are granted for the specified access level.
  ///
  /// - Parameter type: The type of access required (.write or .full)
  /// - Returns: true if the required permission level is granted
  func hasPermission(for type: CalendarPermissionType = .full) -> Bool {
    let access = effectiveAccess()

    switch type {
    case .full:
      // Reading requires full access; a write-only grant does not cover it.
      return access == .full
    case .write:
      return access == .full || access == .writeOnly
    }
  }

  // Info.plist usage-description keys. The declaration checks and the error
  // messages must name the same keys, so both go through these constants and
  // the shared descriptionExample map.
  private static let legacyUsageKey = "NSCalendarsUsageDescription"
  private static let fullAccessUsageKey = "NSCalendarsFullAccessUsageDescription"
  private static let writeOnlyUsageKey = "NSCalendarsWriteOnlyAccessUsageDescription"

  private static let descriptionExamples: [String: String] = [
    legacyUsageKey: "Access your calendar to view and manage events.",
    fullAccessUsageKey: "Full access to view and edit your calendar events.",
    writeOnlyUsageKey: "Add events without reading existing events.",
  ]

  private func isDescriptionDeclared(_ key: String) -> Bool {
    let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
    return !(value?.isEmpty ?? true)
  }

  private func missingDescriptionError(_ title: String, keys: [String]) -> PermissionError {
    var errorMessage = "\(title) not declared in Info.plist.\n\n"
    errorMessage += "Add the following to ios/Runner/Info.plist:"
    for key in keys {
      errorMessage += "\n<key>\(key)</key>"
      errorMessage += "\n<string>\(PermissionService.descriptionExamples[key] ?? "")</string>"
    }

    return PermissionError(code: PlatformExceptionCodes.permissionsNotDeclared, message: errorMessage)
  }

  private func missingWriteOnlyDescriptionError() -> PermissionError {
    missingDescriptionError(
      "Write-only calendar usage description",
      keys: [PermissionService.writeOnlyUsageKey])
  }

  private func missingFullAccessDescriptionError() -> PermissionError {
    missingDescriptionError(
      "Full-access calendar usage description",
      keys: [PermissionService.fullAccessUsageKey])
  }

  /// The no-keys-at-all error. Lists every key so following the advice once
  /// satisfies both the status guard and any later request on any OS version —
  /// naming only the legacy key would fix `hasPermissions` and then fail again
  /// on an iOS 17+ request, which demands the tier-specific keys.
  private func missingUsageDescriptionError() -> PermissionError {
    missingDescriptionError(
      "Calendar usage description",
      keys: [
        PermissionService.fullAccessUsageKey,
        PermissionService.writeOnlyUsageKey,
        PermissionService.legacyUsageKey,
      ])
  }

  /// Verifies the Info.plist declares the usage description the request needs.
  ///
  /// On iOS 17+ each request variant **requires** its own key: full access
  /// (`requestFullAccessToEvents`) needs `NSCalendarsFullAccessUsageDescription`
  /// and write-only needs `NSCalendarsWriteOnlyAccessUsageDescription` — the
  /// legacy `NSCalendarsUsageDescription` no longer satisfies either, and
  /// without the matching key the OS raises an exception, so we surface a
  /// clear error instead of crashing. iOS 16 and below uses only the legacy key.
  private func checkUsageDescriptionDeclared(writeOnly: Bool) -> PermissionError? {
    if #available(iOS 17.0, *) {
      if writeOnly {
        return isDescriptionDeclared(PermissionService.writeOnlyUsageKey)
          ? nil : missingWriteOnlyDescriptionError()
      }
      return isDescriptionDeclared(PermissionService.fullAccessUsageKey)
        ? nil : missingFullAccessDescriptionError()
    }

    return isDescriptionDeclared(PermissionService.legacyUsageKey)
      ? nil : missingDescriptionError(
        "Calendar usage description", keys: [PermissionService.legacyUsageKey])
  }

  func hasPermissions() -> Result<String, PermissionError> {
    // A status check triggers no prompt, so any declared calendar usage
    // description — legacy, full-access, or write-only — satisfies the
    // configuration guard. An add-only app that declares only the write-only
    // key can still check status.
    guard isDescriptionDeclared(PermissionService.legacyUsageKey)
      || isDescriptionDeclared(PermissionService.fullAccessUsageKey)
      || isDescriptionDeclared(PermissionService.writeOnlyUsageKey) else {
      return .failure(missingUsageDescriptionError())
    }

    return .success(effectiveAccess().statusString)
  }

  /// Requests calendar access from the user.
  /// - Parameter writeOnly: when `true`, asks for add-only (write-only) access
  ///   where the OS supports it (iOS 17+). On iOS 16 and below write-only does
  ///   not exist, so the request falls back to full access regardless.
  func requestPermissions(
    writeOnly: Bool,
    completion: @escaping (Result<String, PermissionError>) -> Void
  ) {
    let access = effectiveAccess()

    // Already hold a tier that satisfies the request? No prompt needed. Full
    // access satisfies any request; write-only satisfies a write-only ask — but
    // it does NOT satisfy a full ask, so a full request while only write-only is
    // held falls through to a request attempt below.
    let alreadySatisfied = access == .full || (writeOnly && access == .writeOnly)

    // denied / restricted can't be changed from inside the app — the user must
    // use Settings — so report them as-is instead of firing a no-op request.
    let terminal = access == .denied || access == .restricted

    if alreadySatisfied || terminal {
      completion(.success(access.statusString))
      return
    }

    // The usage-description key is only needed once we actually fire an OS
    // request, so the check sits after the early returns — an app that ships
    // without the (iOS 17+) tier key must still get its already-granted or
    // terminal status back rather than a configuration error.
    if let error = checkUsageDescriptionDeclared(writeOnly: writeOnly) {
      completion(.failure(error))
      return
    }

    // Otherwise attempt the request. This prompts on a fresh notDetermined, and
    // also on a full request while only write-only is held — iOS re-presents the
    // dialog asking for full access and upgrades the app in-app if the user
    // agrees.
    authorization.request(writeOnly: writeOnly) { granted, tier in
      guard granted else {
        // Re-read rather than reporting denied outright, so a refused *full*
        // request while write-only is already held still reports the tier the
        // caller actually holds. Only when nothing resolves at all — the OS
        // still says notDetermined and nothing was recorded — do we answer
        // denied: the handler just told us the user said no, and reporting
        // "we never asked" would send callers down the wrong branch (#134's
        // stale window, pointing the other way).
        let access = self.effectiveAccess()
        completion(
          .success(
            access == .notDetermined ? PermissionService.statusDenied : access.statusString))
        return
      }
      // Record before replying: the caller's very next call may gate on this,
      // and the OS status can still read notDetermined at that point (#134).
      self.recordGrant(tier)
      completion(.success(EffectiveAccess(granted: tier).statusString))
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}
