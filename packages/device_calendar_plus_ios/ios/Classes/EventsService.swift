import EventKit
import EventKitUI

extension EKEventAvailability {
  var stringValue: String {
    switch self {
    case .notSupported:
      return "notSupported"
    case .busy:
      return "busy"
    case .free:
      return "free"
    case .tentative:
      return "tentative"
    case .unavailable:
      return "unavailable"
    @unknown default:
      return "notSupported"
    }
  }
}

extension EKEventStatus {
  var stringValue: String {
    switch self {
    case .none:
      return "none"
    case .confirmed:
      return "confirmed"
    case .tentative:
      return "tentative"
    case .canceled:
      return "canceled"
    @unknown default:
      return "none"
    }
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
    // Generate instanceId
    let startMillis = Int64(event.startDate.timeIntervalSince1970 * 1000)
    let eventId = event.eventIdentifier ?? ""
    let instanceId: String
    if event.hasRecurrenceRules {
      instanceId = "\(eventId)@\(startMillis)"
    } else {
      instanceId = eventId
    }
    
    var eventMap: [String: Any] = [
      "eventId": eventId,
      "instanceId": instanceId,
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
    var startDate = event.startDate!
    var endDate = event.endDate!
    
    // For all-day events, iOS returns dates in UTC representing "floating" dates
    // We need to convert them to the device's local timezone to preserve the calendar date
    // Example: "Jan 1, 2022" in UTC should become "Jan 1, 2022 00:00" in local time
    if event.isAllDay {
      // For end date: iOS sets end time to 23:59:59, so add 1 second to get midnight (open interval)
      endDate = endDate.addingTimeInterval(1)
      
      // Extract date components from UTC dates
      let utcCalendar = Calendar(identifier: .gregorian)
      let startComponents = utcCalendar.dateComponents([.year, .month, .day], from: startDate)
      let endComponents = utcCalendar.dateComponents([.year, .month, .day], from: endDate)
      
      // Create dates in local timezone with same calendar date components
      var localCalendar = Calendar.current
      localCalendar.timeZone = TimeZone.current
      if let localStartDate = localCalendar.date(from: startComponents) {
        startDate = localStartDate
      }
      if let localEndDate = localCalendar.date(from: endComponents) {
        endDate = localEndDate
      }
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
    
    // Set isRecurring flag
    eventMap["isRecurring"] = event.hasRecurrenceRules
    
    return eventMap
  }
  
  func getEvent(
    instanceId: String,
    completion: @escaping (Result<[String: Any]?, CalendarError>) -> Void
  ) {
    // Check permission
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Parse instanceId: "eventId" or "eventId@timestamp"
    let parts = instanceId.split(separator: "@", maxSplits: 1)
    let eventId = String(parts[0])
    
    if parts.count == 2, let timestampMillis = Int64(parts[1]) {
      // Recurring event with timestamp
      let occurrenceDate = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
      
      // Query ±1 second around the exact occurrence time
      // We use a small window since we have the precise timestamp
      let startDate = occurrenceDate.addingTimeInterval(-1)
      let endDate = occurrenceDate.addingTimeInterval(1)
      
      let predicate = eventStore.predicateForEvents(
        withStart: startDate,
        end: endDate,
        calendars: nil
      )
      
      let events = eventStore.events(matching: predicate)
      
      // Find the closest matching instance
      let matchingEvents = events.filter { $0.eventIdentifier == eventId }
      let closestEvent = matchingEvents.min(by: { 
        abs($0.startDate.timeIntervalSince(occurrenceDate)) < abs($1.startDate.timeIntervalSince(occurrenceDate))
      })
      
      if let closestEvent = closestEvent {
        completion(.success(eventToMap(event: closestEvent)))
      } else {
        completion(.success(nil))
      }
    } else {
      // Non-recurring event or master event
      if let event = eventStore.event(withIdentifier: eventId) {
        completion(.success(eventToMap(event: event)))
      } else {
        completion(.success(nil))
      }
    }
  }
  
  func showEvent(
    instanceId: String,
    completion: @escaping (Result<EKEventViewController?, CalendarError>) -> Void
  ) {
    // Check permission
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Parse instanceId: "eventId" or "eventId@timestamp"
    let parts = instanceId.split(separator: "@", maxSplits: 1)
    let eventId = String(parts[0])
    let occurrenceDate: Date?
    
    if parts.count == 2, let timestampMillis = Int64(parts[1]) {
      occurrenceDate = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
    } else {
      occurrenceDate = nil
    }
    
    // Fetch the event for modal presentation
    let event: EKEvent?
    
    if let occurrenceDate = occurrenceDate {
      // Query ±1 second around the exact occurrence time
      // We use a small window since we have the precise timestamp
      let startDate = occurrenceDate.addingTimeInterval(-1)
      let endDate = occurrenceDate.addingTimeInterval(1)
      
      let predicate = eventStore.predicateForEvents(
        withStart: startDate,
        end: endDate,
        calendars: nil
      )
      
      let events = eventStore.events(matching: predicate)
      let matchingEvents = events.filter { $0.eventIdentifier == eventId }
      
      // Find the closest match to the occurrence date
      event = matchingEvents.min(by: { abs($0.startDate.timeIntervalSince(occurrenceDate)) < abs($1.startDate.timeIntervalSince(occurrenceDate)) })
    } else {
      // Get master event directly
      event = eventStore.event(withIdentifier: eventId)
    }
    
    // Check if event was found
    guard let foundEvent = event else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with instance ID: \(instanceId)"
      )))
      return
    }
    
    // Create event view controller
    let eventViewController = EKEventViewController()
    eventViewController.event = foundEvent
    eventViewController.allowsEditing = true
    eventViewController.allowsCalendarPreview = true
    
    completion(.success(eventViewController))
  }
  
  func createEvent(
    calendarId: String,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    description: String?,
    location: String?,
    timeZone: String?,
    availability: String,
    completion: @escaping (Result<String, CalendarError>) -> Void
  ) {
    // Check permission
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Get the calendar
    guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Calendar with ID \(calendarId) not found"
      )))
      return
    }
    
    // Create the event
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = title
    event.startDate = startDate
    event.endDate = endDate
    event.isAllDay = isAllDay
    
    // Set optional properties
    if let description = description {
      event.notes = description
    }
    
    if let location = location {
      event.location = location
    }
    
    // Set timezone (nil for all-day events)
    if !isAllDay, let timeZoneIdentifier = timeZone {
      event.timeZone = TimeZone(identifier: timeZoneIdentifier)
    }
    
    // Map availability string to EKEventAvailability
    switch availability {
    case "free":
      event.availability = .free
    case "tentative":
      event.availability = .tentative
    case "unavailable":
      event.availability = .unavailable
    default: // "busy" or default
      event.availability = .busy
    }
    
    // Save the event
    do {
      try eventStore.save(event, span: .thisEvent)
      
      // Return the event ID
      if let eventId = event.eventIdentifier {
        completion(.success(eventId))
      } else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.operationFailed,
          message: "Failed to get event ID after creation"
        )))
      }
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to save event: \(error.localizedDescription)"
      )))
    }
  }
  
  func deleteEvent(
    instanceId: String,
    deleteAllInstances: Bool,
    completion: @escaping (Result<Void, CalendarError>) -> Void
  ) {
    // Check permission
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Parse instanceId: "eventId" or "eventId@timestamp"
    let parts = instanceId.split(separator: "@", maxSplits: 1)
    let eventId = String(parts[0])
    
    // Fetch the event
    let event: EKEvent?
    
    if parts.count == 2, let timestampMillis = Int64(parts[1]) {
      // Recurring event with timestamp
      let occurrenceDate = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
      
      // Query ±1 second around the exact occurrence time
      let startDate = occurrenceDate.addingTimeInterval(-1)
      let endDate = occurrenceDate.addingTimeInterval(1)
      
      let predicate = eventStore.predicateForEvents(
        withStart: startDate,
        end: endDate,
        calendars: nil
      )
      
      let events = eventStore.events(matching: predicate)
      let matchingEvents = events.filter { $0.eventIdentifier == eventId }
      
      // Find the closest match
      event = matchingEvents.min(by: {
        abs($0.startDate.timeIntervalSince(occurrenceDate)) < abs($1.startDate.timeIntervalSince(occurrenceDate))
      })
    } else {
      // Non-recurring event or master event
      event = eventStore.event(withIdentifier: eventId)
    }
    
    // Check if event was found
    guard let foundEvent = event else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with instance ID: \(instanceId)"
      )))
      return
    }
    
    // Determine the span for deletion
    let span: EKSpan = deleteAllInstances ? .futureEvents : .thisEvent
    
    // Delete the event
    do {
      try eventStore.remove(foundEvent, span: span)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to delete event: \(error.localizedDescription)"
      )))
    }
  }
  
  func updateEvent(
    instanceId: String,
    updateAllInstances: Bool,
    title: String?,
    startDate: Date?,
    endDate: Date?,
    description: String?,
    location: String?,
    isAllDay: Bool?,
    timeZone: String?,
    availability: String?,
    completion: @escaping (Result<Void, CalendarError>) -> Void
  ) {
    // Check permission
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }
    
    // Parse instanceId: "eventId" or "eventId@timestamp"
    let parts = instanceId.split(separator: "@", maxSplits: 1)
    let eventId = String(parts[0])
    
    // Fetch the event (use same logic as deleteEvent)
    let event: EKEvent?
    
    if parts.count == 2, let timestampMillis = Int64(parts[1]) {
      // Recurring event with timestamp
      let occurrenceDate = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
      
      // Query ±1 second around the exact occurrence time
      let startDateQuery = occurrenceDate.addingTimeInterval(-1)
      let endDateQuery = occurrenceDate.addingTimeInterval(1)
      
      let predicate = eventStore.predicateForEvents(
        withStart: startDateQuery,
        end: endDateQuery,
        calendars: nil
      )
      
      let events = eventStore.events(matching: predicate)
      let matchingEvents = events.filter { $0.eventIdentifier == eventId }
      
      // Find the closest match
      event = matchingEvents.min(by: {
        abs($0.startDate.timeIntervalSince(occurrenceDate)) < abs($1.startDate.timeIntervalSince(occurrenceDate))
      })
    } else {
      // Non-recurring event or master event
      event = eventStore.event(withIdentifier: eventId)
    }
    
    // Check if event was found
    guard let foundEvent = event else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with instance ID: \(instanceId)"
      )))
      return
    }
    
    // Update only provided fields
    if let title = title {
      foundEvent.title = title
    }
    
    if let description = description {
      foundEvent.notes = description
    }
    
    if let location = location {
      foundEvent.location = location
    }
    
    // Determine if event is/will be all-day
    let effectiveIsAllDay = isAllDay ?? foundEvent.isAllDay
    
    // Update isAllDay if provided
    if let isAllDay = isAllDay {
      foundEvent.isAllDay = isAllDay
    }
    
    // Update dates if provided
    if let startDate = startDate {
      foundEvent.startDate = startDate
    }
    if let endDate = endDate {
      foundEvent.endDate = endDate
    }
    
    // Update timezone
    // For all-day events, timezone should be nil
    // For timed events, set the timezone if provided
    if effectiveIsAllDay {
      foundEvent.timeZone = nil
    } else if let timeZoneIdentifier = timeZone {
      foundEvent.timeZone = TimeZone(identifier: timeZoneIdentifier)
    }
    
    // Update availability if provided
    if let availability = availability {
      switch availability {
      case "free":
        foundEvent.availability = .free
      case "tentative":
        foundEvent.availability = .tentative
      case "unavailable":
        foundEvent.availability = .unavailable
      default: // "busy" or default
        foundEvent.availability = .busy
      }
    }
    
    // Determine the span for update
    let span: EKSpan = updateAllInstances ? .futureEvents : .thisEvent
    
    // Save the event
    do {
      try eventStore.save(foundEvent, span: span)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to update event: \(error.localizedDescription)"
      )))
    }
  }
}

