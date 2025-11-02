import EventKit

class CalendarService {
  private let eventStore: EKEventStore
  private let permissionService: PermissionService
  
  init(eventStore: EKEventStore, permissionService: PermissionService) {
    self.eventStore = eventStore
    self.permissionService = permissionService
  }
  
  func listCalendars(completion: @escaping (Result<[[String: Any]], CalendarError>) -> Void) {
    // Check current permission status - listing calendars requires full access (reading)
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Get all event calendars
    let calendars = eventStore.calendars(for: .event)
    let defaultCalendar = eventStore.defaultCalendarForNewEvents
    
    var calendarMaps: [[String: Any]] = []
    
    for calendar in calendars {
      var calendarMap: [String: Any] = [
        "id": calendar.calendarIdentifier,
        "name": calendar.title,
        "readOnly": !calendar.allowsContentModifications,
        "isPrimary": calendar == defaultCalendar,
        "hidden": false // iOS doesn't expose hidden calendars
      ]
      
      // Add color if available
      if let cgColor = calendar.cgColor {
        calendarMap["colorHex"] = colorToHex(cgColor: cgColor)
      }
      
      // Add account name from source
      if let sourceTitle = calendar.source?.title {
        calendarMap["accountName"] = sourceTitle
      }
      
      // Add account type from source
      if let sourceType = calendar.source?.sourceType {
        calendarMap["accountType"] = sourceTypeToString(sourceType: sourceType)
      }
      
      calendarMaps.append(calendarMap)
    }
    
    completion(.success(calendarMaps))
  }
  
  private func colorToHex(cgColor: CGColor) -> String {
    guard let components = cgColor.components, components.count >= 3 else {
      return "#000000"
    }
    
    let r = Int(components[0] * 255.0)
    let g = Int(components[1] * 255.0)
    let b = Int(components[2] * 255.0)
    
    return String(format: "#%02X%02X%02X", r, g, b)
  }
  
  private func sourceTypeToString(sourceType: EKSourceType) -> String {
    switch sourceType {
    case .local:
      return "local"
    case .exchange:
      return "exchange"
    case .calDAV:
      return "caldav"
    case .mobileMe:
      return "mobileme"
    case .subscribed:
      return "subscribed"
    case .birthdays:
      return "birthdays"
    @unknown default:
      return "unknown"
    }
  }
}

struct CalendarError: Error {
  let code: String
  let message: String
}

