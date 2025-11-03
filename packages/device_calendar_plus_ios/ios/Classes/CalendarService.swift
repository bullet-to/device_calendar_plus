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
        calendarMap["colorHex"] = ColorHelper.colorToHex(cgColor: cgColor)
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
  
  func createCalendar(name: String, colorHex: String?, completion: @escaping (Result<String, CalendarError>) -> Void) {
    // Check current permission status - creating calendars requires full access (writing)
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Find the local source - this is the only writable source for local calendars
    guard let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.unknownError,
        message: "Could not find local calendar source"
      )))
      return
    }
    
    // Create a new calendar
    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.source = localSource
    calendar.title = name
    
    // Set color if provided
    if let colorHex = colorHex {
      calendar.cgColor = ColorHelper.hexToColor(hex: colorHex)
    }
    
    // Save the calendar
    do {
      try eventStore.saveCalendar(calendar, commit: true)
      completion(.success(calendar.calendarIdentifier))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.unknownError,
        message: "Failed to save calendar: \(error.localizedDescription)"
      )))
    }
  }
  
  func updateCalendar(calendarId: String, name: String?, colorHex: String?, completion: @escaping (Result<Void, CalendarError>) -> Void) {
    // Check current permission status - updating calendars requires full access (writing)
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Find the calendar by ID
    guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Calendar with ID \(calendarId) not found"
      )))
      return
    }
    
    // Check if calendar is modifiable
    guard calendar.allowsContentModifications else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Calendar is read-only and cannot be modified"
      )))
      return
    }
    
    // Update name if provided
    if let name = name {
      calendar.title = name
    }
    
    // Update color if provided
    if let colorHex = colorHex {
      calendar.cgColor = ColorHelper.hexToColor(hex: colorHex)
    }
    
    // Save the calendar
    do {
      try eventStore.saveCalendar(calendar, commit: true)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.unknownError,
        message: "Failed to update calendar: \(error.localizedDescription)"
      )))
    }
  }
  
  func deleteCalendar(calendarId: String, completion: @escaping (Result<Void, CalendarError>) -> Void) {
    // Check current permission status - deleting calendars requires full access (writing)
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Find the calendar by ID
    guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Calendar with ID \(calendarId) not found"
      )))
      return
    }
    
    // Delete the calendar
    do {
      try eventStore.removeCalendar(calendar, commit: true)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.unknownError,
        message: "Failed to delete calendar: \(error.localizedDescription)"
      )))
    }
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

