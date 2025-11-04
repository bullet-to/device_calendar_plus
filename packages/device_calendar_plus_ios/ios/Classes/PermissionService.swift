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
  
  private func checkUsageDescriptionDeclared() -> PermissionError? {
    let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCalendarsUsageDescription") as? String
    
    if usageDescription == nil || usageDescription?.isEmpty == true {
      var errorMessage = "Calendar usage description not declared in Info.plist.\n\n"
      errorMessage += "Add the following to ios/Runner/Info.plist:\n"
      errorMessage += "<key>NSCalendarsUsageDescription</key>\n"
      errorMessage += "<string>Access your calendar to view and manage events.</string>\n"
      errorMessage += "<key>NSCalendarsWriteOnlyAccessUsageDescription</key>\n"
      errorMessage += "<string>Add events without reading existing events.</string>"
      
      return PermissionError(code: PlatformExceptionCodes.permissionsNotDeclared, message: errorMessage)
    }
    
    return nil
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
    if let error = checkUsageDescriptionDeclared() {
      return .failure(error)
    }
    
    return .success(getCurrentPermissionStatus())
  }
  
  func requestPermissions(completion: @escaping (Result<String, PermissionError>) -> Void) {
    if let error = checkUsageDescriptionDeclared() {
      completion(.failure(error))
      return
    }
    
    let currentStatus = getCurrentPermissionStatus()
    
    // If already determined (granted, denied, restricted, or writeOnly), return immediately
    if currentStatus != PermissionService.statusNotDetermined {
      completion(.success(currentStatus))
      return
    }
    
    // Request permissions if not determined
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents { granted, error in
        let status = granted ? PermissionService.statusGranted : PermissionService.statusDenied
        completion(.success(status))
      }
    } else {
      eventStore.requestAccess(to: .event) { granted, error in
        let status = granted ? PermissionService.statusGranted : PermissionService.statusDenied
        completion(.success(status))
      }
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}

