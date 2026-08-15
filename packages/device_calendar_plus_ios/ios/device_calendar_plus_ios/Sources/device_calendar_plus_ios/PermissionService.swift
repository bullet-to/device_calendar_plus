import EventKit
import Foundation

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

class PermissionService {
  /// Fires the OS access request for a tier and reports whether it was granted.
  /// Injected so tests can drive the grant path without a real system prompt.
  typealias AccessRequest = (_ writeOnly: Bool, _ completion: @escaping (Bool, Error?) -> Void) -> Void

  private let authorizationStatus: () -> EKAuthorizationStatus
  private let requestAccess: AccessRequest

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

  init(
    eventStore: EKEventStore,
    authorizationStatus: @escaping () -> EKAuthorizationStatus = {
      EKEventStore.authorizationStatus(for: .event)
    },
    requestAccess: AccessRequest? = nil
  ) {
    self.authorizationStatus = authorizationStatus
    self.requestAccess = requestAccess ?? { writeOnly, completion in
      if #available(iOS 17.0, *) {
        if writeOnly {
          eventStore.requestWriteOnlyAccessToEvents(completion: completion)
        } else {
          eventStore.requestFullAccessToEvents(completion: completion)
        }
      } else {
        // iOS 16 and below: only full access exists.
        eventStore.requestAccess(to: .event, completion: completion)
      }
    }
  }

  /// Remembers the tier the user just granted this process.
  ///
  /// On iOS 17+ `EKEventStore.authorizationStatus(for:)` can still report
  /// `.notDetermined` for a short while after the request handler has already
  /// confirmed a grant (#134), which made the very next call fail its
  /// permission gate until the app was restarted. The recorded tier is the
  /// fallback the `.notDetermined` branches consult.
  ///
  /// Nothing ever clears it, and nothing needs to: it is only ever consulted
  /// while the OS says `.notDetermined`, so any real status the OS goes on to
  /// report — including a `.denied` from a Settings revocation — wins outright.
  private func recordGrant(_ type: CalendarPermissionType) {
    grantLock.lock()
    defer { grantLock.unlock() }
    // Only ever upgrade: the record must never report less access than the
    // user actually granted this process.
    if recordedGrant == nil || type == .full {
      recordedGrant = type
    }
  }

  private func currentRecordedGrant() -> CalendarPermissionType? {
    grantLock.lock()
    defer { grantLock.unlock() }
    return recordedGrant
  }

  /// Whether the grant recorded in this process covers `type`. A full grant
  /// covers both tiers; a write-only grant covers only write, so it must not
  /// satisfy a `.full` check.
  private func recordedGrantSatisfies(_ type: CalendarPermissionType) -> Bool {
    switch (currentRecordedGrant(), type) {
    case (.full?, _), (.write?, .write):
      return true
    default:
      return false
    }
  }

  private static func statusString(for type: CalendarPermissionType) -> String {
    switch type {
    case .full:
      return statusGranted
    case .write:
      return statusWriteOnly
    }
  }

  /// Checks if calendar permissions are granted for the specified access level.
  ///
  /// `.notDetermined` is the only status that falls back to the grant recorded
  /// in this process — a real `.denied` (a Settings revocation, say) is
  /// honoured immediately and is never masked by an earlier grant.
  ///
  /// - Parameter type: The type of access required (.write or .full)
  /// - Returns: true if the required permission level is granted
  func hasPermission(for type: CalendarPermissionType = .full) -> Bool {
    let status = authorizationStatus()

    if #available(iOS 17.0, *) {
      switch type {
      case .full:
        // For full access (reading), need fullAccess only
        switch status {
        case .fullAccess:
          return true
        case .notDetermined:
          return recordedGrantSatisfies(type)
        case .writeOnly, .denied, .restricted:
          return false
        @unknown default:
          return false
        }

      case .write:
        // For write-only operations, writeOnly or fullAccess is fine
        switch status {
        case .fullAccess, .writeOnly:
          return true
        case .notDetermined:
          return recordedGrantSatisfies(type)
        case .denied, .restricted:
          return false
        @unknown default:
          return false
        }
      }
    } else {
      // iOS 16 and below only has .authorized (which is full access), so a
      // recorded grant there is always full and satisfies either type.
      switch status {
      case .authorized:
        return true
      case .notDetermined:
        return recordedGrantSatisfies(type)
      case .denied, .restricted:
        return false
      @unknown default:
        return false
      }
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
  
  /// The tier to report to Dart. As in `hasPermission`, only `.notDetermined`
  /// falls back to the grant recorded in this process, so the two never
  /// disagree about what the app currently holds.
  private func getCurrentPermissionStatus() -> String {
    let currentStatus = authorizationStatus()

    if #available(iOS 17.0, *) {
      switch currentStatus {
      case .fullAccess:
        return PermissionService.statusGranted
      case .writeOnly:
        return PermissionService.statusWriteOnly
      case .denied:
        return PermissionService.statusDenied
      case .restricted:
        return PermissionService.statusRestricted
      case .notDetermined:
        return recordedGrantStatus() ?? PermissionService.statusNotDetermined
      @unknown default:
        return PermissionService.statusDenied
      }
    } else {
      switch currentStatus {
      case .authorized:
        return PermissionService.statusGranted
      case .denied:
        return PermissionService.statusDenied
      case .restricted:
        return PermissionService.statusRestricted
      case .notDetermined:
        return recordedGrantStatus() ?? PermissionService.statusNotDetermined
      @unknown default:
        return PermissionService.statusDenied
      }
    }
  }

  private func recordedGrantStatus() -> String? {
    currentRecordedGrant().map(PermissionService.statusString(for:))
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

    return .success(getCurrentPermissionStatus())
  }
  
  /// Requests calendar access from the user.
  /// - Parameter writeOnly: when `true`, asks for add-only (write-only) access
  ///   where the OS supports it (iOS 17+). On iOS 16 and below write-only does
  ///   not exist, so the request falls back to full access regardless.
  func requestPermissions(
    writeOnly: Bool,
    completion: @escaping (Result<String, PermissionError>) -> Void
  ) {
    let currentStatus = getCurrentPermissionStatus()

    // Already hold a tier that satisfies the request? No prompt needed. Full
    // access satisfies any request; write-only satisfies a write-only ask — but
    // it does NOT satisfy a full ask, so a full request while only write-only is
    // held falls through to a request attempt below.
    let alreadySatisfied = currentStatus == PermissionService.statusGranted
      || (writeOnly && currentStatus == PermissionService.statusWriteOnly)

    // denied / restricted can't be changed from inside the app — the user must
    // use Settings — so report them as-is instead of firing a no-op request.
    let terminal = currentStatus == PermissionService.statusDenied
      || currentStatus == PermissionService.statusRestricted

    if alreadySatisfied || terminal {
      completion(.success(currentStatus))
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
    // agrees. On a non-grant we re-read the real status so the caller still sees
    // the tier they actually hold (e.g. writeOnly), not a misleading denied.
    // Report the tier we asked for on a grant; on a non-grant re-read the real
    // status.
    let grantedType: CalendarPermissionType
    if #available(iOS 17.0, *) {
      grantedType = writeOnly ? .write : .full
    } else {
      // iOS 16 and below: only full access exists, so any grant is full access.
      grantedType = .full
    }

    requestAccess(writeOnly) { granted, _ in
      guard granted else {
        completion(.success(self.getCurrentPermissionStatus()))
        return
      }
      // Record before replying: the caller's very next call may gate on this,
      // and the OS status can still read notDetermined at that point (#134).
      self.recordGrant(grantedType)
      completion(.success(PermissionService.statusString(for: grantedType)))
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}

