import EventKit

extension EKEventAvailability {
  var stringValue: String {
    String(describing: self)
  }
}

extension EKEventStatus {
  var stringValue: String {
    String(describing: self)
  }
}

class EventsService {
  private let eventStore: EKEventStore
  private let permissionService: PermissionService
  
  init(eventStore: EKEventStore, permissionService: PermissionService) {
    self.eventStore = eventStore
    self.permissionService = permissionService
  }
  
  func retrieveEvents(
    startDate: Date,
    endDate: Date,
    calendarIds: [String]?,
    completion: @escaping (Result<[[String: Any]], CalendarError>) -> Void
  ) {
    // Check permission
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Filter calendars if IDs provided
    var calendars: [EKCalendar]?
    if let calendarIds = calendarIds, !calendarIds.isEmpty {
      calendars = calendarIds.compactMap { calendarId in
        eventStore.calendar(withIdentifier: calendarId)
      }
      
      // If no valid calendars found, return empty list
      if calendars?.isEmpty ?? true {
        completion(.success([]))
        return
      }
    }
    
    // Create predicate for events
    // Note: iOS automatically limits to 4-year spans
    let predicate = eventStore.predicateForEvents(
      withStart: startDate,
      end: endDate,
      calendars: calendars
    )
    
    // Fetch events
    let events = eventStore.events(matching: predicate)
    
    // Convert to maps
    let eventMaps = events.map { event in
      eventToMap(event: event)
    }
    
    completion(.success(eventMaps))
  }
  
  private func eventToMap(event: EKEvent) -> [String: Any] {
    var eventMap: [String: Any] = [
      "eventId": event.eventIdentifier,
      "calendarId": event.calendar.calendarIdentifier,
      "title": event.title ?? "",
      "isAllDay": event.isAllDay
    ]
    
    // Add optional fields
    if let notes = event.notes {
      eventMap["description"] = notes
    }
    
    if let location = event.location {
      eventMap["location"] = location
    }
    
    // Convert dates to milliseconds since epoch
    let startDate = event.startDate!
    var endDate = event.endDate!
    
    // For all-day events, iOS sets end time to 23:59:59, but we want midnight (open interval)
    if event.isAllDay {
      endDate = endDate.addingTimeInterval(1)
    }
    
    eventMap["startDate"] = Int64(startDate.timeIntervalSince1970 * 1000)
    eventMap["endDate"] = Int64(endDate.timeIntervalSince1970 * 1000)
    
    // Map availability and status to strings
    eventMap["availability"] = event.availability.stringValue
    eventMap["status"] = event.status.stringValue
    
    // Add timezone for timed events (null for all-day events)
    if !event.isAllDay, let timeZone = event.timeZone {
      eventMap["timeZone"] = timeZone.identifier
    }
    
    return eventMap
  }
}

