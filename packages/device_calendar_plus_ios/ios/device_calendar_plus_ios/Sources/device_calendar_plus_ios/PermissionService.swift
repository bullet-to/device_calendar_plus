import EventKit
import Foundation

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

/// The calendar access this app holds, normalised across iOS versions.
///
/// EventKit's own `EKAuthorizationStatus` means different things on either
/// side of iOS 17 (`.authorized` there is full access; `.writeOnly` does not
/// exist). The `CalendarAuthorization` seam flattens that away, so nothing
/// above it has to ask what OS it is on.
enum CalendarAccess {
  case notDetermined
  case denied
  case restricted
  case writeOnly
  case fullAccess

  init(granted type: CalendarPermissionType) {
    switch type {
    case .full:
      self = .fullAccess
    case .write:
      self = .writeOnly
    }
  }

  /// The tier lattice, defined once: full access covers everything, a
  /// write-only grant covers writes but never reads.
  func satisfies(_ required: CalendarPermissionType) -> Bool {
    switch required {
    case .full:
      return self == .fullAccess
    case .write:
      return self == .fullAccess || self == .writeOnly
    }
  }

  /// Can't be changed from inside the app — the user must use Settings.
  var isTerminal: Bool { self == .denied || self == .restricted }

  /// The method-channel wire format: Dart's `CalendarPermissionStatus` parses
  /// these by name, so they are contract rather than display strings. Used only
  /// at the channel boundary, and defined only here.
  var wireValue: String {
    switch self {
    case .fullAccess:
      return "granted"
    case .writeOnly:
      return "writeOnly"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    }
  }
}

/// The OS-level calendar authorization seam.
///
/// Injected into `PermissionService` so tests can drive the whole grant path
/// — on either side of the iOS 17 divide — without a real system prompt. The
/// caller picks the tier: deciding which tier an ask resolves to is policy,
/// and policy lives in `PermissionService`, leaving implementations to do
/// nothing but report the OS's capabilities and dispatch to it.
protocol CalendarAuthorization {
  /// Whether this OS has the iOS 17+ write-only tier at all. The only version
  /// question `PermissionService` asks, and it asks it of the seam, so the
  /// pre-17 world is a test fixture rather than a runtime accident.
  var supportsWriteOnly: Bool { get }

  var status: CalendarAccess { get }

  /// Fires the OS prompt for `tier` and reports whether it was granted.
  func request(_ tier: CalendarPermissionType, completion: @escaping (_ granted: Bool) -> Void)
}

/// The production `CalendarAuthorization`, backed by EventKit. Every
/// `#available` check in the permission stack lives here.
struct EventKitAuthorization: CalendarAuthorization {
  let eventStore: EKEventStore

  var supportsWriteOnly: Bool {
    if #available(iOS 17.0, *) {
      return true
    }
    return false
  }

  var status: CalendarAccess {
    let status = EKEventStore.authorizationStatus(for: .event)

    if #available(iOS 17.0, *) {
      switch status {
      case .fullAccess:
        return .fullAccess
      case .writeOnly:
        return .writeOnly
      case .denied:
        return .denied
      case .restricted:
        return .restricted
      case .notDetermined:
        return .notDetermined
      @unknown default:
        return .denied
      }
    }

    // iOS 16 and below only has .authorized, which is full access.
    switch status {
    case .authorized:
      return .fullAccess
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .notDetermined:
      return .notDetermined
    // Not `@unknown default`: the iOS 17+ `.writeOnly` case is unreachable
    // here but still counts against exhaustiveness, and a plain `default`
    // maps it to the same `.denied` without the warning.
    default:
      return .denied
    }
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

/// The answer the OS request handler already gave us, if it has answered.
///
/// On iOS 17+ `EKEventStore.authorizationStatus(for:)` can still report
/// `.notDetermined` for a short while afterwards (#134), which made the very
/// next call fail its permission gate until the app was restarted. This is the
/// fallback the `.notDetermined` branch consults.
///
/// Nothing ever clears it, and nothing needs to: it is only consulted while the
/// OS says `.notDetermined`, so a revocation always wins, and iOS terminates
/// the app when its privacy settings change, so the record cannot outlive the
/// answer it describes.
///
/// Process-wide by design: the answer belongs to the app, not to one
/// `PermissionService`, and a `FlutterEngineGroup` or add-to-app host builds
/// one service per engine. Production injects `shared`; tests inject a fresh
/// instance to stay isolated from each other.
final class AccessRecord {
  static let shared = AccessRecord()

  /// Read from the provider queue (the data endpoints) and from the main
  /// thread (the modal endpoints and the method-channel handlers), and written
  /// from whichever thread EventKit calls the request handler on, so every
  /// access goes through `lock`.
  private let lock = NSLock()
  private var access: CalendarAccess?

  /// Remembers the answer the user just gave.
  func record(_ answer: CalendarAccess) {
    lock.lock()
    defer { lock.unlock() }
    // Only ever upgrade, so the record can never under-report what is held: a
    // refused full upgrade must not erase the write-only grant behind it.
    if access == nil || answer == .fullAccess {
      access = answer
    }
  }

  var current: CalendarAccess? {
    lock.lock()
    defer { lock.unlock() }
    return access
  }
}

/// The permission policy: which tier an ask resolves to, which grants satisfy
/// which gates, and what Dart is told. It holds no version knowledge of its own
/// — the `CalendarAuthorization` seam answers that.
class PermissionService {
  private let authorization: CalendarAuthorization
  private let accessRecord: AccessRecord

  init(authorization: CalendarAuthorization, accessRecord: AccessRecord) {
    self.authorization = authorization
    self.accessRecord = accessRecord
  }

  /// The access this app effectively holds. Every decision — the gates, the
  /// status reported to Dart, and whether a request is worth firing — is made
  /// on this, so they can never disagree.
  ///
  /// Falls back to the record while — and only while — the OS still says
  /// `.notDetermined`, so a real `.denied` (a Settings revocation, say) is
  /// honoured immediately and is never masked by an earlier answer.
  private func effectiveAccess() -> CalendarAccess {
    let status = authorization.status
    guard status == .notDetermined else { return status }
    return accessRecord.current ?? .notDetermined
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
  ///
  /// Takes the resolved tier rather than the caller's raw `writeOnly` flag, so
  /// the "which tier is this ask" question is answered exactly once, in
  /// `requestPermissions`.
  private func checkUsageDescriptionDeclared(for tier: CalendarPermissionType) -> PermissionError? {
    guard authorization.supportsWriteOnly else {
      return isDescriptionDeclared(PermissionService.legacyUsageKey)
        ? nil : missingDescriptionError(
          "Calendar usage description", keys: [PermissionService.legacyUsageKey])
    }

    switch tier {
    case .write:
      return isDescriptionDeclared(PermissionService.writeOnlyUsageKey)
        ? nil : missingWriteOnlyDescriptionError()
    case .full:
      return isDescriptionDeclared(PermissionService.fullAccessUsageKey)
        ? nil : missingFullAccessDescriptionError()
    }
  }

  func hasPermissions() -> Result<CalendarAccess, PermissionError> {
    // A status check triggers no prompt, so any declared calendar usage
    // description — legacy, full-access, or write-only — satisfies the
    // configuration guard. An add-only app that declares only the write-only
    // key can still check status.
    guard isDescriptionDeclared(PermissionService.legacyUsageKey)
      || isDescriptionDeclared(PermissionService.fullAccessUsageKey)
      || isDescriptionDeclared(PermissionService.writeOnlyUsageKey) else {
      return .failure(missingUsageDescriptionError())
    }

    return .success(effectiveAccess())
  }

  /// Requests calendar access from the user.
  /// - Parameter writeOnly: when `true`, asks for add-only (write-only) access
  ///   where the OS supports it (iOS 17+). On iOS 16 and below write-only does
  ///   not exist, so the request falls back to full access regardless.
  func requestPermissions(
    writeOnly: Bool,
    completion: @escaping (Result<CalendarAccess, PermissionError>) -> Void
  ) {
    // The tier this ask resolves to. Write-only exists only where the OS
    // supports it, so elsewhere every ask resolves to full access — the one
    // place the version difference is decided.
    let tier: CalendarPermissionType =
      writeOnly && authorization.supportsWriteOnly ? .write : .full

    let access = effectiveAccess()

    // Nothing to prompt for if we already hold a tier that satisfies the ask
    // (a full request while only write-only is held does *not*, so it falls
    // through), or if the answer can only be changed in Settings.
    if access.satisfies(tier) || access.isTerminal {
      completion(.success(access))
      return
    }

    // The usage-description key is only needed once we actually fire an OS
    // request, so the check sits after the early returns — an app that ships
    // without the (iOS 17+) tier key must still get its already-granted or
    // terminal status back rather than a configuration error.
    if let error = checkUsageDescriptionDeclared(for: tier) {
      completion(.failure(error))
      return
    }

    // Otherwise attempt the request. This prompts on a fresh notDetermined, and
    // also on a full request while only write-only is held — iOS re-presents the
    // dialog asking for full access and upgrades the app in-app if the user
    // agrees.
    authorization.request(tier) { granted in
      guard granted else {
        // Record the refusal too, or `hasPermissions` would go on reporting
        // "we never asked" for the whole stale window. The record only
        // upgrades, so a refused *full* ask leaves an earlier write-only grant
        // standing and re-reading reports that rather than denied.
        self.accessRecord.record(.denied)
        completion(.success(self.effectiveAccess()))
        return
      }
      // Record before replying: the caller's very next call may gate on this,
      // and the OS status can still read notDetermined at that point (#134).
      let access = CalendarAccess(granted: tier)
      self.accessRecord.record(access)
      completion(.success(access))
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}
