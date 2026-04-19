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
  
  func createCalendar(name: String, colorHex: String?, sourceId: String?, completion: @escaping (Result<String, CalendarError>) -> Void) {
    // Check current permission status - creating calendars requires full access (writing)
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }

    let source: EKSource
    if let sourceId = sourceId {
      // Find source by identifier
      guard let found = eventStore.sources.first(where: { $0.sourceIdentifier == sourceId }) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.notFound,
          message: "Source not found with identifier: \(sourceId)"
        )))
        return
      }
      source = found
    } else {
      // Use the best available writable source (tiered fallback)
      guard let fallback = eventStore.defaultCalendarForNewEvents?.source
          ?? eventStore.sources.first(where: { $0.sourceType == .calDAV })
          ?? eventStore.sources.first(where: { $0.sourceType == .local })
      else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.calendarUnavailable,
          message: "Could not find a writable calendar source"
        )))
        return
      }
      source = fallback
    }

    // Create a new calendar
    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.source = source
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
        code: PlatformExceptionCodes.operationFailed,
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
        code: PlatformExceptionCodes.notFound,
        message: "Calendar with ID \(calendarId) not found"
      )))
      return
    }
    
    // Check if calendar is modifiable
    guard calendar.allowsContentModifications else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.readOnly,
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
        code: PlatformExceptionCodes.operationFailed,
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
        code: PlatformExceptionCodes.notFound,
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
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to delete calendar: \(error.localizedDescription)"
      )))
    }
  }
  
  func listSources(completion: @escaping (Result<[[String: Any]], CalendarError>) -> Void) {
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }

    let sources = eventStore.sources.map { source -> [String: Any] in
      return [
        "id": source.sourceIdentifier,
        "accountName": source.title,
        "accountType": sourceTypeToString(sourceType: source.sourceType),
        "type": sourceTypeToCalendarSourceType(source.sourceType),
        "supportsCalendarCreation": sourceSupportsCreation(source.sourceType),
      ]
    }

    completion(.success(sources))
  }

  private func sourceTypeToCalendarSourceType(_ type: EKSourceType) -> String {
    switch type {
    case .local: return "local"
    case .calDAV: return "calDav"
    case .exchange: return "exchange"
    case .subscribed: return "subscribed"
    case .birthdays: return "birthdays"
    default: return "other"
    }
  }

  private func sourceSupportsCreation(_ type: EKSourceType) -> Bool {
    switch type {
    case .local, .calDAV, .exchange: return true
    default: return false
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

