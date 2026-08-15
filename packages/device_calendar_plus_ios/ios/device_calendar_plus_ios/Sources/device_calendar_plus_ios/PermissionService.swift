import EventKit
import Foundation

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

/// The OS-level calendar authorization seam.
///
/// Injected into `PermissionService` so tests can drive the whole grant path
/// without a real system prompt. The caller picks the tier — deciding which
/// tier an ask resolves to is policy, and policy lives in `PermissionService`
/// — leaving implementations to do nothing but dispatch to the OS.
protocol CalendarAuthorization {
  var status: EKAuthorizationStatus { get }

  /// Fires the OS prompt for `tier` and reports whether it was granted.
  func request(_ tier: CalendarPermissionType, completion: @escaping (_ granted: Bool) -> Void)
}

/// The production `CalendarAuthorization`, backed by EventKit.
struct EventKitAuthorization: CalendarAuthorization {
  let eventStore: EKEventStore

  var status: EKAuthorizationStatus {
    EKEventStore.authorizationStatus(for: .event)
  }

  func request(_ tier: CalendarPermissionType, completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      switch tier {
      case .write:
        eventStore.requestWriteOnlyAccessToEvents { granted, _ in completion(granted) }
      case .full:
        eventStore.requestFullAccessToEvents { granted, _ in completion(granted) }
      }
    } else {
      // iOS 16 and below: only full access exists, and `PermissionService`
      // resolves every ask to `.full` there, so there is nothing to branch on.
      eventStore.requestAccess(to: .event) { granted, _ in completion(granted) }
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
    // Only ever upgrade, so the record can never under-report what was granted.
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
  /// on this, so they can never disagree.
  ///
  /// The raw values are the wire format: they must match Dart's
  /// `CalendarPermissionStatus` enum, and this is their only definition.
  enum EffectiveAccess: String {
    case full = "granted"
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

    /// The tier lattice, defined once: full access covers everything, a
    /// write-only grant covers writes but never reads.
    func satisfies(_ required: CalendarPermissionType) -> Bool {
      switch required {
      case .full:
        return self == .full
      case .write:
        return self == .full || self == .writeOnly
      }
    }

    /// Can't be changed from inside the app — the user must use Settings.
    var isTerminal: Bool { self == .denied || self == .restricted }
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
      // Not `@unknown default`: the iOS 17+ `.fullAccess` / `.writeOnly` cases
      // are unreachable here but still count against exhaustiveness, and a
      // plain `default` maps them to the same `.denied` without the warning.
      default:
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
    effectiveAccess().satisfies(type)
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

    return .success(effectiveAccess().rawValue)
  }

  /// Requests calendar access from the user.
  /// - Parameter writeOnly: when `true`, asks for add-only (write-only) access
  ///   where the OS supports it (iOS 17+). On iOS 16 and below write-only does
  ///   not exist, so the request falls back to full access regardless.
  func requestPermissions(
    writeOnly: Bool,
    completion: @escaping (Result<String, PermissionError>) -> Void
  ) {
    // The tier this ask resolves to. Write-only exists only on iOS 17+, so
    // older versions resolve every ask to full access — the one place the
    // version difference is decided.
    let tier: CalendarPermissionType = {
      if #available(iOS 17.0, *) {
        return writeOnly ? .write : .full
      }
      return .full
    }()

    let access = effectiveAccess()

    // Nothing to prompt for if we already hold a tier that satisfies the ask
    // (a full request while only write-only is held does *not*, so it falls
    // through), or if the answer can only be changed in Settings.
    if access.satisfies(tier) || access.isTerminal {
      completion(.success(access.rawValue))
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
    authorization.request(tier) { granted in
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
          .success(access == .notDetermined ? EffectiveAccess.denied.rawValue : access.rawValue))
        return
      }
      // Record before replying: the caller's very next call may gate on this,
      // and the OS status can still read notDetermined at that point (#134).
      self.recordGrant(tier)
      completion(.success(EffectiveAccess(granted: tier).rawValue))
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}
