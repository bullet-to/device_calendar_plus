import EventKit

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

class PermissionService {
  private let eventStore: EKEventStore
  
  // Permission status values matching CalendarPermissionStatus enum
  static let statusGranted = "granted"
  static let statusWriteOnly = "writeOnly"
  static let statusDenied = "denied"
  static let statusRestricted = "restricted"
  static let statusNotDetermined = "notDetermined"
  
  init(eventStore: EKEventStore) {
    self.eventStore = eventStore
  }
  
  /// Checks if calendar permissions are granted for the specified access level.
  /// - Parameter type: The type of access required (.write or .full)
  /// - Returns: true if the required permission level is granted
  func hasPermission(for type: CalendarPermissionType = .full) -> Bool {
    if #available(iOS 17.0, *) {
      let status = EKEventStore.authorizationStatus(for: .event)
      
      switch type {
      case .full:
        // For full access (reading), need fullAccess only
        switch status {
        case .fullAccess:
          return true
        case .writeOnly, .denied, .restricted, .notDetermined:
          return false
        @unknown default:
          return false
        }
        
      case .write:
        // For write-only operations, writeOnly or fullAccess is fine
        switch status {
        case .fullAccess, .writeOnly:
          return true
        case .denied, .restricted, .notDetermined:
          return false
        @unknown default:
          return false
        }
      }
    } else {
      // iOS 16 and below only has .authorized (which is full access)
      let status = EKEventStore.authorizationStatus(for: .event)
      switch status {
      case .authorized:
        return true
      case .denied, .restricted, .notDetermined:
        return false
      @unknown default:
        return false
      }
    }
  }
  
  private func isDescriptionDeclared(_ key: String) -> Bool {
    let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
    return !(value?.isEmpty ?? true)
  }

  private func missingWriteOnlyDescriptionError() -> PermissionError {
    var errorMessage = "Write-only calendar usage description not declared in Info.plist.\n\n"
    errorMessage += "Add the following to ios/Runner/Info.plist:\n"
    errorMessage += "<key>NSCalendarsWriteOnlyAccessUsageDescription</key>\n"
    errorMessage += "<string>Add events without reading existing events.</string>"

    return PermissionError(code: PlatformExceptionCodes.permissionsNotDeclared, message: errorMessage)
  }

  private func missingUsageDescriptionError() -> PermissionError {
    var errorMessage = "Calendar usage description not declared in Info.plist.\n\n"
    errorMessage += "Add the following to ios/Runner/Info.plist:\n"
    errorMessage += "<key>NSCalendarsUsageDescription</key>\n"
    errorMessage += "<string>Access your calendar to view and manage events.</string>\n"
    errorMessage += "<key>NSCalendarsWriteOnlyAccessUsageDescription</key>\n"
    errorMessage += "<string>Add events without reading existing events.</string>"

    return PermissionError(code: PlatformExceptionCodes.permissionsNotDeclared, message: errorMessage)
  }

  /// Verifies the Info.plist declares the usage description the request needs.
  ///
  /// A write-only request on iOS 17+ goes through `requestWriteOnlyAccessToEvents`,
  /// which **requires** `NSCalendarsWriteOnlyAccessUsageDescription` — without it
  /// the OS raises an exception, so we surface a clear error instead of crashing.
  /// Every other path uses `NSCalendarsUsageDescription`.
  private func checkUsageDescriptionDeclared(writeOnly: Bool) -> PermissionError? {
    if writeOnly, #available(iOS 17.0, *) {
      return isDescriptionDeclared("NSCalendarsWriteOnlyAccessUsageDescription")
        ? nil : missingWriteOnlyDescriptionError()
    }

    return isDescriptionDeclared("NSCalendarsUsageDescription")
      ? nil : missingUsageDescriptionError()
  }
  
  private func getCurrentPermissionStatus() -> String {
    if #available(iOS 17.0, *) {
      let currentStatus = EKEventStore.authorizationStatus(for: .event)
      
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
        return PermissionService.statusNotDetermined
      @unknown default:
        return PermissionService.statusDenied
      }
    } else {
      let currentStatus = EKEventStore.authorizationStatus(for: .event)
      
      switch currentStatus {
      case .authorized:
        return PermissionService.statusGranted
      case .denied:
        return PermissionService.statusDenied
      case .restricted:
        return PermissionService.statusRestricted
      case .notDetermined:
        return PermissionService.statusNotDetermined
      @unknown default:
        return PermissionService.statusDenied
      }
    }
  }
  
  func hasPermissions() -> Result<String, PermissionError> {
    // A status check triggers no prompt, so any declared calendar usage
    // description — full or write-only — satisfies the configuration guard. An
    // add-only app that declares only the write-only key can still check status.
    guard isDescriptionDeclared("NSCalendarsUsageDescription")
      || isDescriptionDeclared("NSCalendarsWriteOnlyAccessUsageDescription") else {
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
    if let error = checkUsageDescriptionDeclared(writeOnly: writeOnly) {
      completion(.failure(error))
      return
    }

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

    // Otherwise attempt the request. This prompts on a fresh notDetermined, and
    // also on a full request while only write-only is held — iOS re-presents the
    // dialog asking for full access and upgrades the app in-app if the user
    // agrees. On a non-grant we re-read the real status so the caller still sees
    // the tier they actually hold (e.g. writeOnly), not a misleading denied.
    let writeOnlySupported: Bool
    if #available(iOS 17.0, *) {
      writeOnlySupported = true
    } else {
      writeOnlySupported = false
    }

    // Report the tier we asked for on a grant; on a non-grant re-read the real
    // status. (iOS 16 has only full access, so a write-only ask there grants
    // full.) One handler serves all three request variants.
    let grantedStatus = (writeOnly && writeOnlySupported)
      ? PermissionService.statusWriteOnly
      : PermissionService.statusGranted
    let handler: (Bool, Error?) -> Void = { granted, _ in
      completion(.success(granted ? grantedStatus : self.getCurrentPermissionStatus()))
    }

    if #available(iOS 17.0, *) {
      if writeOnly {
        eventStore.requestWriteOnlyAccessToEvents(completion: handler)
      } else {
        eventStore.requestFullAccessToEvents(completion: handler)
      }
    } else {
      eventStore.requestAccess(to: .event, completion: handler)
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}

