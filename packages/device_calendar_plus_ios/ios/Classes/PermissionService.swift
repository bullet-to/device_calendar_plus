import EventKit

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

class PermissionService {
  private let eventStore: EKEventStore
  
  // Permission status codes matching CalendarPermissionStatus enum
  static let statusGranted = 0
  static let statusWriteOnly = 1
  static let statusDenied = 2
  static let statusRestricted = 3
  static let statusNotDetermined = 4
  
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
  
  func requestPermissions(completion: @escaping (Result<Int, PermissionError>) -> Void) {
    // Check if required Info.plist keys are present
    let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCalendarsUsageDescription") as? String
    
    if usageDescription == nil || usageDescription?.isEmpty == true {
      var errorMessage = "Calendar usage description not declared in Info.plist.\n\n"
      errorMessage += "Add the following to ios/Runner/Info.plist:\n"
      errorMessage += "<key>NSCalendarsUsageDescription</key>\n"
      errorMessage += "<string>Access your calendar to view and manage events.</string>\n"
      errorMessage += "<key>NSCalendarsWriteOnlyAccessUsageDescription</key>\n"
      errorMessage += "<string>Add events without reading existing events.</string>"

      
      completion(.failure(PermissionError(code: PlatformExceptionCodes.permissionsNotDeclared, message: errorMessage)))
      return
    }
    
    if #available(iOS 17.0, *) {
      // iOS 17+ has separate read and write access
      let currentStatus = EKEventStore.authorizationStatus(for: .event)
      
      switch currentStatus {
      case .fullAccess:
        completion(.success(PermissionService.statusGranted))
      case .writeOnly:
        completion(.success(PermissionService.statusWriteOnly))
      case .denied:
        completion(.success(PermissionService.statusDenied))
      case .restricted:
        completion(.success(PermissionService.statusRestricted))
      case .notDetermined:
        // Request full access
        eventStore.requestFullAccessToEvents { granted, error in
          let status = granted ? PermissionService.statusGranted : PermissionService.statusDenied
          completion(.success(status))
        }
      @unknown default:
        completion(.success(PermissionService.statusDenied))
      }
    } else {
      // iOS 16 and below
      let currentStatus = EKEventStore.authorizationStatus(for: .event)
      
      switch currentStatus {
      case .authorized:
        completion(.success(PermissionService.statusGranted))
      case .denied:
        completion(.success(PermissionService.statusDenied))
      case .restricted:
        completion(.success(PermissionService.statusRestricted))
      case .notDetermined:
        eventStore.requestAccess(to: .event) { granted, error in
          let status = granted ? PermissionService.statusGranted : PermissionService.statusDenied
          completion(.success(status))
        }
      @unknown default:
        completion(.success(PermissionService.statusDenied))
      }
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}

