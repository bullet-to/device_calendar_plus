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

    if let url = event.url {
      eventMap["url"] = url.absoluteString
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

    // Serialize recurrence rule to RRULE string
    if event.hasRecurrenceRules, let rule = event.recurrenceRules?.first {
      eventMap["recurrenceRule"] = ekRecurrenceRuleToRruleString(rule)
    }

    // Serialize attendees
    if let participants = event.attendees, !participants.isEmpty {
      let attendees: [[String: Any]] = participants.compactMap { participant in
        // Skip the organizer
        if participant.participantRole == .chair {
          return nil
        }

        var attendeeMap: [String: Any] = [
          "role": participantRoleToString(participant.participantRole),
          "status": participantStatusToString(participant.participantStatus),
        ]

        if let name = participant.name {
          attendeeMap["name"] = name
        }

        // Email is embedded in the URL property as mailto:
        let urlString = participant.url.absoluteString
        if urlString.hasPrefix("mailto:") {
          attendeeMap["emailAddress"] = String(urlString.dropFirst(7))
        }

        return attendeeMap
      }

      if !attendees.isEmpty {
        eventMap["attendees"] = attendees
      }
    }

    return eventMap
  }

  private func participantRoleToString(_ role: EKParticipantRole) -> String {
    switch role {
    case .required: return "required"
    case .optional: return "optional"
    case .chair: return "chair"
    case .nonParticipant: return "nonParticipant"
    case .unknown: return "required"
    @unknown default: return "required"
    }
  }

  private func participantStatusToString(_ status: EKParticipantStatus) -> String {
    switch status {
    case .accepted: return "accepted"
    case .declined: return "declined"
    case .tentative: return "tentative"
    case .pending: return "pending"
    case .delegated: return "delegated"
    case .completed: return "completed"
    case .inProcess: return "inProcess"
    case .unknown: return "none"
    @unknown default: return "none"
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
    edit: Bool = false,
    completion: @escaping (Result<UIViewController?, CalendarError>) -> Void
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
    
    if edit {
      let editViewController = EKEventEditViewController()
      editViewController.eventStore = eventStore
      editViewController.event = foundEvent
      completion(.success(editViewController))
    } else {
      let eventViewController = EKEventViewController()
      eventViewController.event = foundEvent
      eventViewController.allowsEditing = true
      eventViewController.allowsCalendarPreview = true
      completion(.success(eventViewController))
    }
  }
  
  func createEvent(
    calendarId: String,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    description: String?,
    location: String?,
    url: String?,
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

    if let urlString = url {
      guard let eventUrl = URL(string: urlString) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "Invalid URL string: \(urlString)"
        )))
        return
      }
      event.url = eventUrl
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
    case "busy":
      event.availability = .busy
    default: // fallback for unknown strings
      event.availability = .busy
    }
    
    // Set recurrence rule if provided
    if let rruleString = recurrenceRule, let rule = parseRecurrenceRule(rruleString) {
      event.recurrenceRules = [rule]
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
  
  // MARK: - Create Event for Modal

  /// Creates an EKEvent with optional pre-fill properties for the native editor.
  /// Returns nil if no pre-fill params are provided (caller uses nil for blank editor).
  func createEventForModal(
    title: String?,
    startDate: Int64?,
    endDate: Int64?,
    description: String?,
    location: String?,
    isAllDay: Bool?,
    recurrenceRule: String?,
    availability: String?,
    completion: @escaping (Result<EKEvent?, CalendarError>) -> Void
  ) {
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }

    // If all params are nil, return nil so the editor opens blank
    if title == nil && startDate == nil && endDate == nil && description == nil &&
       location == nil && isAllDay == nil && recurrenceRule == nil && availability == nil {
      completion(.success(nil))
      return
    }

    let event = EKEvent(eventStore: eventStore)

    if let title = title { event.title = title }
    if let startMillis = startDate {
      event.startDate = Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000.0)
    }
    if let endMillis = endDate {
      event.endDate = Date(timeIntervalSince1970: TimeInterval(endMillis) / 1000.0)
    }
    if let description = description { event.notes = description }
    if let location = location { event.location = location }
    if let isAllDay = isAllDay { event.isAllDay = isAllDay }

    if let availability = availability {
      switch availability {
      case "free": event.availability = .free
      case "tentative": event.availability = .tentative
      case "unavailable": event.availability = .unavailable
      default: event.availability = .busy
      }
    }

    if let rruleString = recurrenceRule, let rule = parseRecurrenceRule(rruleString) {
      event.recurrenceRules = [rule]
    }

    completion(.success(event))
  }

  // MARK: - RRULE <-> EKRecurrenceRule conversion
  
  /// Parses an RRULE string into an EKRecurrenceRule.
  private func parseRecurrenceRule(_ rrule: String) -> EKRecurrenceRule? {
    var params: [String: String] = [:]
    let ruleStr = rrule.hasPrefix("RRULE:") ? String(rrule.dropFirst(6)) : rrule
    
    for part in ruleStr.components(separatedBy: ";") {
      let kv = part.components(separatedBy: "=")
      if kv.count == 2 {
        params[kv[0].uppercased()] = kv[1]
      }
    }
    
    guard let freqStr = params["FREQ"] else { return nil }
    
    let frequency: EKRecurrenceFrequency
    switch freqStr {
    case "DAILY": frequency = .daily
    case "WEEKLY": frequency = .weekly
    case "MONTHLY": frequency = .monthly
    case "YEARLY": frequency = .yearly
    default: return nil
    }
    
    let interval = Int(params["INTERVAL"] ?? "1") ?? 1
    
    // Parse end condition
    var end: EKRecurrenceEnd? = nil
    if let countStr = params["COUNT"], let count = Int(countStr) {
      end = EKRecurrenceEnd(occurrenceCount: count)
    } else if let untilStr = params["UNTIL"] {
      if let date = parseRruleDate(untilStr) {
        end = EKRecurrenceEnd(end: date)
      }
    }
    
    // Parse BYDAY (supports plain codes like "TU" and positional like "2TU", "-1FR")
    var daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil
    if let byDayStr = params["BYDAY"] {
      daysOfTheWeek = byDayStr.components(separatedBy: ",").compactMap { dayStr in
        parseByDayValue(dayStr.trimmingCharacters(in: .whitespaces))
      }
      if daysOfTheWeek?.isEmpty ?? true { daysOfTheWeek = nil }
    }
    
    // Parse BYMONTHDAY (supports comma-separated values)
    var daysOfTheMonth: [NSNumber]? = nil
    if let str = params["BYMONTHDAY"] {
      let days = str.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
      if !days.isEmpty { daysOfTheMonth = days.map { NSNumber(value: $0) } }
    }

    // Parse BYMONTH (supports comma-separated values)
    var monthsOfTheYear: [NSNumber]? = nil
    if let str = params["BYMONTH"] {
      let months = str.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
      if !months.isEmpty { monthsOfTheYear = months.map { NSNumber(value: $0) } }
    }
    
    // Parse BYSETPOS (supports comma-separated values)
    var setPositions: [NSNumber]? = nil
    if let str = params["BYSETPOS"] {
      let positions = str.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
      if !positions.isEmpty { setPositions = positions.map { NSNumber(value: $0) } }
    }

    return EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: interval,
      daysOfTheWeek: daysOfTheWeek,
      daysOfTheMonth: daysOfTheMonth,
      monthsOfTheYear: monthsOfTheYear,
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: setPositions,
      end: end
    )
  }
  
  /// Parses a single BYDAY value like "TU", "2TU", or "-1FR".
  private func parseByDayValue(_ value: String) -> EKRecurrenceDayOfWeek? {
    let dayMap: [String: EKWeekday] = [
      "SU": .sunday, "MO": .monday, "TU": .tuesday, "WE": .wednesday,
      "TH": .thursday, "FR": .friday, "SA": .saturday,
    ]

    // Try positional format first (e.g., "2TU", "-1FR")
    if value.count > 2 {
      let dayCode = String(value.suffix(2))
      let numStr = String(value.dropLast(2))
      if let weekday = dayMap[dayCode], let weekNumber = Int(numStr), weekNumber != 0 {
        return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
      }
    }

    // Plain day code (e.g., "TU")
    if let weekday = dayMap[value] {
      return EKRecurrenceDayOfWeek(weekday)
    }

    return nil
  }

  /// Parses RRULE date: YYYYMMDD or YYYYMMDDTHHMMSSZ.
  private func parseRruleDate(_ dateStr: String) -> Date? {
    let clean = dateStr.replacingOccurrences(of: "Z", with: "")
    guard clean.count >= 8 else { return nil }
    
    let year = Int(clean.prefix(4)) ?? 0
    let month = Int(clean.dropFirst(4).prefix(2)) ?? 0
    let day = Int(clean.dropFirst(6).prefix(2)) ?? 0
    
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.timeZone = TimeZone(identifier: "UTC")
    
    if clean.count >= 15, clean.dropFirst(8).first == "T" {
      let timeStr = clean.dropFirst(9)
      components.hour = Int(timeStr.prefix(2)) ?? 0
      components.minute = Int(timeStr.dropFirst(2).prefix(2)) ?? 0
      components.second = Int(timeStr.dropFirst(4).prefix(2)) ?? 0
    } else {
      components.hour = 0
      components.minute = 0
      components.second = 0
    }
    
    return Calendar(identifier: .gregorian).date(from: components)
  }
  
  /// Serializes an EKRecurrenceRule back to an RRULE string.
  private func ekRecurrenceRuleToRruleString(_ rule: EKRecurrenceRule) -> String {
    var parts: [String] = []
    
    // Frequency
    switch rule.frequency {
    case .daily: parts.append("FREQ=DAILY")
    case .weekly: parts.append("FREQ=WEEKLY")
    case .monthly: parts.append("FREQ=MONTHLY")
    case .yearly: parts.append("FREQ=YEARLY")
    @unknown default: parts.append("FREQ=DAILY")
    }
    
    // Interval
    if rule.interval > 1 {
      parts.append("INTERVAL=\(rule.interval)")
    }
    
    // BYDAY
    if let daysOfWeek = rule.daysOfTheWeek, !daysOfWeek.isEmpty {
      let dayStrs = daysOfWeek.map { dow -> String in
        let code: String
        switch dow.dayOfTheWeek {
        case .sunday: code = "SU"
        case .monday: code = "MO"
        case .tuesday: code = "TU"
        case .wednesday: code = "WE"
        case .thursday: code = "TH"
        case .friday: code = "FR"
        case .saturday: code = "SA"
        @unknown default: code = "MO"
        }
        if dow.weekNumber != 0 {
          return "\(dow.weekNumber)\(code)"
        }
        return code
      }
      parts.append("BYDAY=\(dayStrs.joined(separator: ","))")
    }
    
    // BYMONTHDAY
    if let daysOfMonth = rule.daysOfTheMonth, !daysOfMonth.isEmpty {
      let dayStrs = daysOfMonth.map { $0.stringValue }
      parts.append("BYMONTHDAY=\(dayStrs.joined(separator: ","))")
    }
    
    // BYMONTH
    if let months = rule.monthsOfTheYear, !months.isEmpty {
      let monthStrs = months.map { $0.stringValue }
      parts.append("BYMONTH=\(monthStrs.joined(separator: ","))")
    }
    
    // BYSETPOS
    if let setPositions = rule.setPositions, !setPositions.isEmpty {
      let posStrs = setPositions.map { $0.stringValue }
      parts.append("BYSETPOS=\(posStrs.joined(separator: ","))")
    }

    // WKST (week start day)
    if rule.firstDayOfTheWeek != 0 {
      let wkstMap: [Int: String] = [
        1: "SU", 2: "MO", 3: "TU", 4: "WE", 5: "TH", 6: "FR", 7: "SA",
      ]
      if let wkst = wkstMap[rule.firstDayOfTheWeek] {
        parts.append("WKST=\(wkst)")
      }
    }

    // End condition
    if let end = rule.recurrenceEnd {
      if end.occurrenceCount > 0 {
        parts.append("COUNT=\(end.occurrenceCount)")
      } else if let endDate = end.endDate {
        let cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        var comps = cal.dateComponents(in: utc, from: endDate)
        let y = String(format: "%04d", comps.year ?? 0)
        let m = String(format: "%02d", comps.month ?? 0)
        let d = String(format: "%02d", comps.day ?? 0)
        let h = comps.hour ?? 0
        let min = comps.minute ?? 0
        let s = comps.second ?? 0
        if h == 0 && min == 0 && s == 0 {
          parts.append("UNTIL=\(y)\(m)\(d)")
        } else {
          parts.append("UNTIL=\(y)\(m)\(d)T\(String(format: "%02d", h))\(String(format: "%02d", min))\(String(format: "%02d", s))Z")
        }
      }
    }
    
    return parts.joined(separator: ";")
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

  /// Updates an event. With a `timestamp`, detaches the occurrence at that
  /// instant from its recurring series and applies the changes to it alone;
  /// without one, updates the event itself (the whole series when recurring).
  func updateEvent(
    eventId: String,
    timestamp: Int64?,
    title: String?,
    startDate: Date?,
    endDate: Date?,
    description: String?,
    location: String?,
    url: String?,
    isAllDay: Bool?,
    timeZone: String?,
    availability: String?,
    clearedFields: [String],
    completion: @escaping (Result<Void, CalendarError>) -> Void)
  {
    // Permission Check
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }

    // Resolve the event to act on: the occurrence at `timestamp` when given,
    // otherwise the event (master) itself.
    let targetEvent: EKEvent?
    if let timestamp = timestamp {
      targetEvent = findOccurrence(eventId: eventId, timestamp: timestamp)
    } else {
      targetEvent = eventStore.event(withIdentifier: eventId)
    }

    guard let foundEvent = targetEvent else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with event ID: \(eventId)"
      )))
      return
    }

    if timestamp != nil && !foundEvent.hasRecurrenceRules {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Event \(eventId) is not recurring; pass a bare event ID instead"
      )))
      return
    }

    // Get new data into event
    if let title = title { foundEvent.title = title }
    if clearedFields.contains("description") {
      foundEvent.notes = nil
    } else if let description = description {
      foundEvent.notes = description
    }
    if clearedFields.contains("location") {
      foundEvent.location = nil
    } else if let location = location {
      foundEvent.location = location
    }
    if clearedFields.contains("url") {
      foundEvent.url = nil
    } else if let url = url {
      foundEvent.url = URL(string: url)
    }
    if let isAllDay = isAllDay { foundEvent.isAllDay = isAllDay }
    if let startDate = startDate { foundEvent.startDate = startDate }
    if let endDate = endDate { foundEvent.endDate = endDate }

    if foundEvent.isAllDay {
      foundEvent.timeZone = nil
    } else if let timeZoneIdentifier = timeZone {
      foundEvent.timeZone = TimeZone(identifier: timeZoneIdentifier)
    }

    if let availabilityStr = availability {
      switch availabilityStr {
      case "free": foundEvent.availability = .free
      case "tentative": foundEvent.availability = .tentative
      case "unavailable": foundEvent.availability = .unavailable
      case "busy": foundEvent.availability = .busy
      default: break
      }
    }

    // An occurrence edit saves .thisEvent, detaching it as an exception. A
    // bare event ID follows the whole series (.futureEvents from the master;
    // on a non-recurring event that behaves like .thisEvent).
    let span: EKSpan = (timestamp != nil) ? .thisEvent : .futureEvents

    // Save updated event
    do {
      try eventStore.save(foundEvent, span: span, commit: true)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to update event: \(error.localizedDescription)"
      )))
    }
  }

  // MARK: - Recurring helpers

  /// Resolves the occurrence of `eventId` nearest to `timestamp` (epoch
  /// millis). EventKit has no direct lookup for a single occurrence, so we
  /// query a tight ±1s window and pick the match whose start is closest.
  ///
  /// Shared by `updateEvent` (instance edits), `updateRecurring`
  /// (`thisAndFollowing`) and `deleteRecurring` (`thisAndFollowing`,
  /// `thisInstance`).
  private func findOccurrence(eventId: String, timestamp: Int64) -> EKEvent? {
    let occurrenceDate = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    let predicate = eventStore.predicateForEvents(
      withStart: occurrenceDate.addingTimeInterval(-1),
      end: occurrenceDate.addingTimeInterval(1),
      calendars: nil
    )
    return eventStore.events(matching: predicate)
      .filter { $0.eventIdentifier == eventId }
      .min(by: {
        abs($0.startDate.timeIntervalSince(occurrenceDate)) <
          abs($1.startDate.timeIntervalSince(occurrenceDate))
      })
  }

  // MARK: - updateRecurring (issue #36)

  /// Keeps the calendar date of `date` but replaces the time-of-day with
  /// `hour`:`minute`, interpreted in `timeZone`. The Swift counterpart of
  /// Android's `replaceTimeOfDay`.
  private func replaceTimeOfDay(
    of date: Date,
    hour: Int,
    minute: Int,
    timeZone: TimeZone
  ) -> Date? {
    var components = Calendar.current.dateComponents(in: timeZone, from: date)
    components.hour = hour
    components.minute = minute
    components.second = 0
    components.nanosecond = 0
    return Calendar.current.date(from: components)
  }

  /// Updates a recurring event, choosing which occurrences the edit affects.
  ///
  /// `span` is "allEvents" (the whole series) or "thisAndFollowing" (split the
  /// series at `timestamp`). On success returns the event ID for the affected
  /// scope — the same ID for "allEvents", the new series' ID for
  /// "thisAndFollowing".
  func updateRecurring(
    eventId: String,
    timestamp: Int64?,
    span: String,
    title: String?,
    startTimeHour: Int?,
    startTimeMinute: Int?,
    durationMinutes: Int?,
    description: String?,
    location: String?,
    url: String?,
    isAllDay: Bool?,
    timeZone: String?,
    availability: String?,
    recurrenceRule: String?,
    clearedFields: [String],
    completion: @escaping (Result<String, CalendarError>) -> Void
  ) {
    // Permission Check
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }

    // Resolve the event to act on. "allEvents" works from the master (the
    // whole series); "thisAndFollowing" works from the specific occurrence
    // at `timestamp`.
    let targetEvent: EKEvent?
    if span == "thisAndFollowing" {
      guard let timestamp = timestamp else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "\(span) requires an occurrence timestamp"
        )))
        return
      }
      targetEvent = findOccurrence(eventId: eventId, timestamp: timestamp)
    } else {
      targetEvent = eventStore.event(withIdentifier: eventId)
    }

    guard let foundEvent = targetEvent else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with event ID: \(eventId)"
      )))
      return
    }

    // All-day events have no time-of-day and only whole-day durations. The
    // Dart layer can only check these against fields in the same call; the
    // stored event's state is enforced here.
    let effectiveIsAllDay = isAllDay ?? foundEvent.isAllDay
    if startTimeHour != nil && effectiveIsAllDay {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "startTime cannot be set on an all-day event"
      )))
      return
    }
    if let durationMinutes = durationMinutes, effectiveIsAllDay, durationMinutes % 1440 != 0 {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "All-day events require whole-day durations"
      )))
      return
    }

    // Apply field changes.
    if let title = title { foundEvent.title = title }
    if clearedFields.contains("description") {
      foundEvent.notes = nil
    } else if let description = description {
      foundEvent.notes = description
    }
    if clearedFields.contains("location") {
      foundEvent.location = nil
    } else if let location = location {
      foundEvent.location = location
    }
    if clearedFields.contains("url") {
      foundEvent.url = nil
    } else if let url = url {
      foundEvent.url = URL(string: url)
    }
    if let isAllDay = isAllDay { foundEvent.isAllDay = isAllDay }

    // Apply time-of-day and/or duration changes. The existing date is
    // preserved; only the time component is replaced.
    var newStart: Date?
    if let hour = startTimeHour {
      let minute = startTimeMinute ?? 0
      guard let replaced = replaceTimeOfDay(
        of: foundEvent.startDate,
        hour: hour,
        minute: minute,
        timeZone: foundEvent.timeZone ?? .current
      ) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.operationFailed,
          message: "Could not apply start time \(hour):\(minute) to the event's start date"
        )))
        return
      }
      newStart = replaced
    }
    if newStart != nil || durationMinutes != nil {
      let duration = durationMinutes.map { TimeInterval($0 * 60) }
        ?? foundEvent.endDate.timeIntervalSince(foundEvent.startDate)
      let start: Date = newStart ?? foundEvent.startDate
      foundEvent.startDate = start
      foundEvent.endDate = start.addingTimeInterval(duration)
    }

    if foundEvent.isAllDay {
      foundEvent.timeZone = nil
    } else if let timeZoneIdentifier = timeZone {
      foundEvent.timeZone = TimeZone(identifier: timeZoneIdentifier)
    }

    if let availabilityStr = availability {
      switch availabilityStr {
      case "free": foundEvent.availability = .free
      case "tentative": foundEvent.availability = .tentative
      case "unavailable": foundEvent.availability = .unavailable
      case "busy": foundEvent.availability = .busy
      default: break
      }
    }

    // Apply the recurrence-rule patch.
    if clearedFields.contains("recurrenceRule") {
      foundEvent.recurrenceRules = nil
    } else if let rruleString = recurrenceRule {
      guard let rule = parseRecurrenceRule(rruleString) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "Invalid recurrence rule: \(rruleString)"
        )))
        return
      }
      foundEvent.recurrenceRules = [rule]
    }

    // Both series spans save with .futureEvents: from the master that is the
    // whole series; from an occurrence it splits the series so that
    // occurrence onward becomes the new series. .futureEvents is also what
    // drops recurrence across a whole series — .thisEvent would only detach
    // one occurrence.
    do {
      try eventStore.save(foundEvent, span: .futureEvents, commit: true)
      completion(.success(foundEvent.eventIdentifier ?? eventId))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to update recurring event: \(error.localizedDescription)"
      )))
    }
  }

  // MARK: - deleteRecurring (issue #43)

  /// Deletes a recurring event, choosing which occurrences are removed.
  ///
  /// `span` is "allEvents" (the whole series), "thisAndFollowing" (the
  /// occurrence at `timestamp` and every later one), or "thisInstance" (only
  /// that occurrence).
  func deleteRecurring(
    eventId: String,
    timestamp: Int64?,
    span: String,
    completion: @escaping (Result<Void, CalendarError>) -> Void
  ) {
    // Permission Check
    guard permissionService.hasPermission(for: .full) else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.permissionDenied,
        message: "Calendar permission denied. Call requestPermissions() first."
      )))
      return
    }

    // Resolve the event to act on. "allEvents" works from the master (the
    // whole series); "thisAndFollowing" and "thisInstance" work from the
    // specific occurrence at `timestamp`.
    let needsOccurrence = (span == "thisAndFollowing" || span == "thisInstance")
    let targetEvent: EKEvent?
    if needsOccurrence {
      guard let timestamp = timestamp else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "\(span) requires an occurrence timestamp"
        )))
        return
      }
      targetEvent = findOccurrence(eventId: eventId, timestamp: timestamp)
    } else {
      targetEvent = eventStore.event(withIdentifier: eventId)
    }

    guard let foundEvent = targetEvent else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Event not found with event ID: \(eventId)"
      )))
      return
    }

    // "thisInstance" removes only the fetched occurrence (.thisEvent).
    // "allEvents" and "thisAndFollowing" use .futureEvents: from the master
    // that removes the whole series; from an occurrence it removes that
    // occurrence and every later one. (.futureEvents on a non-recurring event
    // behaves like .thisEvent.)
    let removeSpan: EKSpan = (span == "thisInstance") ? .thisEvent : .futureEvents

    do {
      try eventStore.remove(foundEvent, span: removeSpan)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to delete recurring event: \(error.localizedDescription)"
      )))
    }
  }
}
