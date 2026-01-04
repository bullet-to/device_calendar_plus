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
    
    // Parse attendees/participants
    if let attendees = event.attendees {
      var attendeeMaps: [[String: Any]] = []
      for participant in attendees {
        var attendeeMap: [String: Any] = [
          "role": participantRoleToString(participant.participantRole),
          "status": participantStatusToString(participant.participantStatus),
          "isOrganizer": participant.participantRole == .chair,
          "isCurrentUser": participant.isCurrentUser
        ]
        
        // Get email from URL (format: "mailto:email@example.com")
        let email = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        attendeeMap["emailAddress"] = email
        
        // Get name if available
        if let name = participant.name {
          attendeeMap["name"] = name
        }
        
        attendeeMaps.append(attendeeMap)
      }
      eventMap["attendees"] = attendeeMaps
    }
    
    return eventMap
  }
  
  private func participantRoleToString(_ role: EKParticipantRole) -> String {
    switch role {
    case .unknown:
      return "none"
    case .required:
      return "required"  
    case .optional:
      return "optional"
    case .chair:
      return "required"  // Chair is the organizer, treat as required
    case .nonParticipant:
      return "resource"
    @unknown default:
      return "none"
    }
  }
  
  private func participantStatusToString(_ status: EKParticipantStatus) -> String {
    switch status {
    case .unknown:
      return "none"
    case .pending:
      return "invited"
    case .accepted:
      return "accepted"
    case .declined:
      return "declined"
    case .tentative:
      return "tentative"
    case .delegated, .completed, .inProcess:
      return "none"
    @unknown default:
      return "none"
    }
  }
  
  func getEvent(
    eventId: String,
    timestamp: Int64?,
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
    
    if let timestampMillis = timestamp {
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
    eventId: String,
    timestamp: Int64?,
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
    
    let occurrenceDate: Date?
    if let timestampMillis = timestamp {
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
        message: "Event not found with event ID: \(eventId)"
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
    recurrenceRule: String?,
    completion: @escaping (Result<String, CalendarError>) -> Void
  ) {
    // Check permission - creating events only requires write access
    guard permissionService.hasPermission(for: .write) else {
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
    
    // Set recurrence rule if provided
    if let rruleString = recurrenceRule, let recurrenceRule = parseRecurrenceRule(rruleString) {
      event.recurrenceRules = [recurrenceRule]
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
    eventId: String,
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
    
    // Fetch the master event by eventId
    guard let event = eventStore.event(withIdentifier: eventId) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with event ID: \(eventId)"
      )))
      return
    }
    
    // Delete the event
    // For recurring events, .futureEvents on the master event deletes the entire series
    // For non-recurring events, .futureEvents behaves the same as .thisEvent
    do {
      try eventStore.remove(event, span: .futureEvents)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to delete event: \(error.localizedDescription)"
      )))
    }
  }
  
  func updateEvent(
    eventId: String,
    title: String?,
    startDate: Date?,
    endDate: Date?,
    description: String?,
    location: String?,
    isAllDay: Bool?,
    timeZone: String?,
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
    
    // Fetch the master event by eventId
    guard let foundEvent = eventStore.event(withIdentifier: eventId) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with event ID: \(eventId)"
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
    
    // Save the event
    // For recurring events, .futureEvents on the master event updates the entire series
    // For non-recurring events, .futureEvents behaves the same as .thisEvent
    do {
      try eventStore.save(foundEvent, span: .futureEvents)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to update event: \(error.localizedDescription)"
      )))
    }
  }
  private func parseRecurrenceRule(_ rrule: String) -> EKRecurrenceRule? {
    // Basic parser for RRULE string generated by Dart RecurrenceRule class
    // Format: FREQ=...;INTERVAL=...;BYDAY=...;BYMONTHDAY=...;COUNT=...;UNTIL=...
    
    var params: [String: String] = [:]
    let parts = rrule.starts(with: "RRULE:") ? String(rrule.dropFirst(6)).components(separatedBy: ";") : rrule.components(separatedBy: ";")
    
    for part in parts {
      let keyValue = part.components(separatedBy: "=")
      if keyValue.count == 2 {
        params[keyValue[0]] = keyValue[1]
      }
    }
    
    // Parse Frequency (Default to Daily if missing/invalid, though it should be present)
    guard let freqStr = params["FREQ"] else { return nil }
    
    var frequency: EKRecurrenceFrequency
    switch freqStr {
    case "DAILY": frequency = .daily
    case "WEEKLY": frequency = .weekly
    case "MONTHLY": frequency = .monthly
    case "YEARLY": frequency = .yearly
    default: frequency = .daily
    }
    
    // Parse Interval (Default 1)
    
    var interval = 1
    if let intervalStr = params["INTERVAL"], let intervalVal = Int(intervalStr) {
      interval = intervalVal
    }
    
    // Parse End Rule (COUNT or UNTIL)
    var end: EKRecurrenceEnd? = nil
    
    if let countStr = params["COUNT"], let count = Int(countStr) {
      end = EKRecurrenceEnd(occurrenceCount: count)
    } else if let untilStr = params["UNTIL"] {
      // Parse UNTIL date: YYYYMMDDTHHMMSSZ or YYYYMMDD
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = TimeZone(identifier: "UTC")
      formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
      
      if let date = formatter.date(from: untilStr) {
        end = EKRecurrenceEnd(end: date)
      } else {
        // Try date only format
        formatter.dateFormat = "yyyyMMdd"
        if let date = formatter.date(from: untilStr) {
             end = EKRecurrenceEnd(end: date)
        }
      }
    }
    
    // Parse Days of Week (BYDAY)
    var daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil
    if let byDayStr = params["BYDAY"] {
      let days = byDayStr.components(separatedBy: ",")
      daysOfTheWeek = days.compactMap { dayStr in
        // Helper to parse day string (e.g. "MO", "TU", "1MO")
        
        switch dayStr {
        case "SU": return EKRecurrenceDayOfWeek(.sunday)
        case "MO": return EKRecurrenceDayOfWeek(.monday)
        case "TU": return EKRecurrenceDayOfWeek(.tuesday)
        case "WE": return EKRecurrenceDayOfWeek(.wednesday)
        case "TH": return EKRecurrenceDayOfWeek(.thursday)
        case "FR": return EKRecurrenceDayOfWeek(.friday)
        case "SA": return EKRecurrenceDayOfWeek(.saturday)
        default: return nil
        }
      }
    }
    
    // Parse Days of Month (BYMONTHDAY)
    var daysOfTheMonth: [NSNumber]? = nil
    if let byMonthDayStr = params["BYMONTHDAY"] {
       if let day = Int(byMonthDayStr) {
         daysOfTheMonth = [NSNumber(value: day)]
       }
    }
    
    return EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: interval,
      daysOfTheWeek: daysOfTheWeek,
      daysOfTheMonth: daysOfTheMonth,
      monthsOfTheYear: nil,
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: nil,
      end: end
    )
  }
  
  func createOrEditEventModal(
      eventId: String?,
      eventData: [String: Any]?,
      completion: @escaping (Result<EKEventEditViewController?, CalendarError>) -> Void
  ) {
      // Check permission
      guard permissionService.hasPermission(for: .write) else {
          completion(.failure(CalendarError(
              code: PlatformExceptionCodes.permissionDenied,
              message: "Calendar permission denied. Call requestPermissions() first."
          )))
          return
      }

      DispatchQueue.main.async {
          if let eventId = eventId {
              // Edit Mode: Fetch existing event
              guard let event = self.eventStore.event(withIdentifier: eventId) else {
                  completion(.failure(CalendarError(
                      code: PlatformExceptionCodes.notFound,
                      message: "Event with ID \(eventId) not found"
                  )))
                  return
              }
              
              // Update properties if eventData provided
              if let eventData = eventData {
                  if let title = eventData["title"] as? String { event.title = title }
                  if let description = eventData["description"] as? String { event.notes = description }
                  if let location = eventData["location"] as? String { event.location = location }
                  if let isAllDay = eventData["isAllDay"] as? Bool { event.isAllDay = isAllDay }
                  
                  if let startDateMillis = eventData["startDate"] as? Int64 {
                      event.startDate = Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000.0)
                  }
                  if let endDateMillis = eventData["endDate"] as? Int64 {
                      event.endDate = Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000.0)
                  }
                  
                  if let timeZoneIdentifier = eventData["timeZone"] as? String, !event.isAllDay {
                      event.timeZone = TimeZone(identifier: timeZoneIdentifier)
                  }
                  
                  // Update recurrence rule
                  if let recurrenceRuleString = eventData["recurrenceRule"] as? String {
                      // Clear existing rules
                      event.recurrenceRules = nil
                      
                      // Add new rule
                      if let rule = self.parseRecurrenceRule(recurrenceRuleString) {
                          event.addRecurrenceRule(rule)
                      }
                  } else if eventData.keys.contains("recurrenceRule") {
                      // Explicitly null/removed in data map -> clear rule
                      event.recurrenceRules = nil
                  }
              }

              let controller = EKEventEditViewController()
              controller.eventStore = self.eventStore
              controller.event = event
              completion(.success(controller))
              
          } else if let eventData = eventData {
              // Create Mode: New event with pre-filled details
              let event = EKEvent(eventStore: self.eventStore)
              
              // Set calendar (default if not specified)
              if let calendarId = eventData["calendarId"] as? String,
                 let calendar = self.eventStore.calendar(withIdentifier: calendarId) {
                  event.calendar = calendar
              } else {
                  event.calendar = self.eventStore.defaultCalendarForNewEvents
              }
              
              // Set basic properties
              if let title = eventData["title"] as? String { event.title = title }
              if let description = eventData["description"] as? String { event.notes = description }
              if let location = eventData["location"] as? String { event.location = location }
              if let isAllDay = eventData["isAllDay"] as? Bool { event.isAllDay = isAllDay }
              
              // Set Dates
              if let startDateMillis = eventData["startDate"] as? Int64 {
                  event.startDate = Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000.0)
              }
              if let endDateMillis = eventData["endDate"] as? Int64 {
                  event.endDate = Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000.0)
              }
              
              // Set TimeZone
              if let timeZoneIdentifier = eventData["timeZone"] as? String, !event.isAllDay {
                  event.timeZone = TimeZone(identifier: timeZoneIdentifier)
              }
              
              // Set Recurrence Rule (if provided)
              if let recurrenceRuleString = eventData["recurrenceRule"] as? String,
                 let rule = self.parseRecurrenceRule(recurrenceRuleString) {
                  event.addRecurrenceRule(rule)
              }
              
              // Note: Attendees (EKParticipant) cannot be created programmatically on iOS.
              // The user must add them manually in the UI.

              let controller = EKEventEditViewController()
              controller.eventStore = self.eventStore
              controller.event = event
              completion(.success(controller))
              
          } else {
              completion(.failure(CalendarError(
                  code: PlatformExceptionCodes.invalidArguments,
                  message: "Either eventId or eventData must be provided"
              )))
          }
      }
  }
}

