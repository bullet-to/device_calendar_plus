import EventKit
import EventKitUI

/// Mirrors Android's MINUTES_PER_DAY — the whole-day duration checks on the
/// two platforms must stay in lockstep.
private let minutesPerDay = 1440

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
    
    // EKEventStore.predicateForEvents silently truncates ranges longer than
    // ~4 years to the first 4 years (#452), so split wide ranges into smaller
    // windows, query each, and merge. A boundary instant can match two adjacent
    // windows, so dedupe by instanceId; listEvents returns events sorted by
    // start date.
    var eventMaps: [[String: Any]] = []
    var seenInstanceIds = Set<String>()
    for window in Self.dateWindows(from: startDate, to: endDate) {
      let predicate = eventStore.predicateForEvents(
        withStart: window.start,
        end: window.end,
        calendars: calendars
      )
      for event in eventStore.events(matching: predicate)
      where seenInstanceIds.insert(instanceId(for: event)).inserted {
        eventMaps.append(eventToMap(event: event))
      }
    }

    // Sort on the map's startDate, not event.startDate: eventToMap rewrites
    // all-day starts from UTC-floating to local midnight, so the two aren't
    // order-equivalent once all-day and timed events mix. startDate is always
    // present in the map, so the cast is a hard invariant, not a fallback.
    eventMaps.sort { lhs, rhs in
      (lhs["startDate"] as! Int64) < (rhs["startDate"] as! Int64)
    }

    completion(.success(eventMaps))
  }

  /// Splits `[start, end]` into consecutive windows no longer than `maxWindow`.
  ///
  /// EKEventStore.predicateForEvents silently truncates ranges longer than
  /// ~4 years to the first 4 years (#452). A conservative ~3-year window stays
  /// safely under that limit (with margin for leap years). For the common case
  /// of a range within one window this returns a single window equal to
  /// `[start, end]`, so there is no extra work. Adjacent windows share their
  /// boundary instant, so callers must dedupe events that match two windows.
  private static func dateWindows(
    from start: Date,
    to end: Date,
    maxWindow: TimeInterval = 3 * 365 * 24 * 60 * 60
  ) -> [(start: Date, end: Date)] {
    guard end > start else { return [(start, end)] }
    var windows: [(start: Date, end: Date)] = []
    var cursor = start
    while cursor < end {
      let next = min(cursor.addingTimeInterval(maxWindow), end)
      windows.append((start: cursor, end: next))
      cursor = next
    }
    return windows
  }
  
  /// Stable identifier for a single fetched event. For a recurring series each
  /// occurrence is distinguished by its start (`eventId@startMillis`); a
  /// non-recurring event is just its `eventId`. Used both to populate the event
  /// map and to dedupe occurrences that match two adjacent query windows.
  private func instanceId(for event: EKEvent) -> String {
    let eventId = event.eventIdentifier ?? ""
    guard event.hasRecurrenceRules else { return eventId }
    let startMillis = Int64(event.startDate.timeIntervalSince1970 * 1000)
    return "\(eventId)@\(startMillis)"
  }

  private func eventToMap(event: EKEvent) -> [String: Any] {
    let eventId = event.eventIdentifier ?? ""

    var eventMap: [String: Any] = [
      "eventId": eventId,
      "instanceId": instanceId(for: event),
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
      // Keep the Edit button: Android's ACTION_VIEW screen also lets the user
      // edit from the view, so allowing it here preserves cross-platform parity.
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
  
  /// Deletes an event. With a `timestamp`, removes only the occurrence at
  /// that instant from its recurring series; without one, deletes the event
  /// itself (the whole series when recurring).
  func deleteEvent(
    eventId: String,
    timestamp: Int64?,
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

    // An occurrence delete removes .thisEvent only. A bare event ID removes
    // the whole series (.futureEvents from the master; on a non-recurring
    // event that behaves like .thisEvent).
    let span: EKSpan = (timestamp != nil) ? .thisEvent : .futureEvents

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

  /// Updates an event. With a `timestamp`, detaches the occurrence at that
  /// instant from its recurring series and applies the changes to it alone;
  /// without one, updates the event itself (the whole series when recurring).
  func updateEvent(
    eventId: String,
    timestamp: Int64?,
    startDate: Date?,
    endDate: Date?,
    patch: EventFieldPatch,
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

    // An occurrence edit leaves an omitted date at the occurrence's own
    // value, so a startDate alone can overtake the end. Reject the inverted
    // range here, before mutating the live EKEvent — matching Android, which
    // computes the same effective range and fails with invalidArguments.
    if timestamp != nil {
      let newStart = startDate ?? foundEvent.startDate!
      let newEnd = endDate ?? foundEvent.endDate!
      if newEnd <= newStart {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "End date must be after the occurrence's start date"
        )))
        return
      }
    }

    // Get new data into event
    patch.apply(to: foundEvent)
    if let startDate = startDate { foundEvent.startDate = startDate }
    if let endDate = endDate { foundEvent.endDate = endDate }
    patch.applyTimeZone(to: foundEvent)

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
  /// Shared by `updateEvent` and `deleteEvent` (instance edits) and
  /// `updateRecurring` and `deleteRecurring` (`thisAndFollowing`).
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

  /// Copies `rule` but caps it to end just before `date`, so the series stops
  /// at the occurrence before `date`. Used to truncate a master series at a
  /// `thisAndFollowing` split point. `EKRecurrenceEnd(end:)` is inclusive, so
  /// the cap sits one second early to keep the split occurrence off the
  /// original series (mirrors Android's `timestamp - 1000`).
  private func ruleTruncated(
    _ rule: EKRecurrenceRule,
    endingBefore date: Date
  ) -> EKRecurrenceRule {
    return EKRecurrenceRule(
      recurrenceWith: rule.frequency,
      interval: rule.interval,
      daysOfTheWeek: rule.daysOfTheWeek,
      daysOfTheMonth: rule.daysOfTheMonth,
      monthsOfTheYear: rule.monthsOfTheYear,
      weeksOfTheYear: rule.weeksOfTheYear,
      daysOfTheYear: rule.daysOfTheYear,
      setPositions: rule.setPositions,
      end: EKRecurrenceEnd(end: date.addingTimeInterval(-1))
    )
  }

  /// Translates `base` by the wall-clock delta from `reference` to `target`,
  /// computed in `timeZone`: shifts by the whole-day difference and sets the
  /// time-of-day to `target`'s. DST-safe — it counts calendar days and sets a
  /// wall-clock time rather than adding a raw interval. For all-day events the
  /// day shifts but the time-of-day is left at the start of day.
  ///
  /// This is the anchor-shift that lets a single `updateRecurring` move both
  /// the time and the day of a series (issue #103). Android's counterpart is
  /// `shiftDate`.
  private func shiftStart(
    _ base: Date,
    reference: Date,
    to target: Date,
    isAllDay: Bool,
    timeZone: TimeZone
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let refDay = calendar.startOfDay(for: reference)
    let targetDay = calendar.startOfDay(for: target)
    let dayDelta = calendar.dateComponents([.day], from: refDay, to: targetDay).day ?? 0
    guard let shiftedDay = calendar.date(byAdding: .day, value: dayDelta, to: base) else {
      return nil
    }
    if isAllDay {
      return calendar.startOfDay(for: shiftedDay)
    }
    let tod = calendar.dateComponents([.hour, .minute, .second], from: target)
    return calendar.date(
      bySettingHour: tod.hour ?? 0,
      minute: tod.minute ?? 0,
      second: tod.second ?? 0,
      of: shiftedDay
    )
  }

  /// Splits a `thisAndFollowing` series at `occurrence` and turns that
  /// occurrence into a standalone non-recurring event, dropping every later
  /// occurrence (earlier ones stay in the original series).
  ///
  /// EventKit can't do this natively: setting `recurrenceRules = nil` and
  /// saving `.futureEvents` has no future series to detach, so it edits the
  /// master and collapses the WHOLE series into one event at the original
  /// start (the `allEvents` outcome). So mirror Android: truncate the master
  /// before the occurrence, then create a fresh standalone event at the split
  /// point.
  ///
  /// `occurrence` must already carry the caller's patched field values; it is
  /// only read here (never saved), so its mutations don't touch the master.
  private func detachThisAndFollowing(
    occurrence: EKEvent,
    eventId: String,
    occurrenceDate: Date,
    completion: @escaping (Result<String, CalendarError>) -> Void
  ) {
    guard let master = eventStore.event(withIdentifier: eventId),
          let masterRule = master.recurrenceRules?.first else {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Could not resolve the master series to split"
      )))
      return
    }

    // Truncate the original series to end just before the split occurrence.
    master.recurrenceRules = [ruleTruncated(masterRule, endingBefore: occurrenceDate)]

    // The standalone carries the occurrence's fields with no recurrence. This
    // field set mirrors Android's `insertEvent` in `updateRecurringThisAndFollowing`.
    let standalone = EKEvent(eventStore: eventStore)
    standalone.calendar = occurrence.calendar
    standalone.title = occurrence.title
    standalone.isAllDay = occurrence.isAllDay
    standalone.startDate = occurrence.startDate
    standalone.endDate = occurrence.endDate
    standalone.notes = occurrence.notes
    standalone.location = occurrence.location
    standalone.url = occurrence.url
    standalone.timeZone = occurrence.timeZone
    standalone.availability = occurrence.availability

    // Two-phase save: stage the truncation uncommitted, then commit both with
    // the standalone. On failure `reset()` discards both so the calendar is
    // left untouched (mirrors Android's roll-back of the new series).
    do {
      try eventStore.save(master, span: .futureEvents, commit: false)
      try eventStore.save(standalone, span: .thisEvent, commit: true)
      completion(.success(standalone.eventIdentifier ?? eventId))
    } catch {
      eventStore.reset()
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to detach occurrence into a standalone event: \(error.localizedDescription)"
      )))
    }
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
    newStartMillis: Int64?,
    durationMinutes: Int?,
    recurrenceRule: String?,
    patch: EventFieldPatch,
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
    let effectiveIsAllDay = patch.isAllDay ?? foundEvent.isAllDay
    if let durationMinutes = durationMinutes, effectiveIsAllDay,
       durationMinutes % minutesPerDay != 0 {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "All-day events require whole-day durations"
      )))
      return
    }

    // Compute the new start and parse the recurrence rule before touching
    // the event. EventKit keeps the fetched EKEvent live in its cache, so
    // every failure exit must happen while it is still unmodified — orphaned
    // mutations could otherwise ride along with a later save.
    // Anchor shift: move the reference occurrence to `newStartMillis` and
    // translate this event's start by the same wall-clock delta (day + time).
    // The reference is the occurrence at `timestamp`, or the series anchor
    // (foundEvent is the master) for `allEvents` with no timestamp.
    var newStart: Date?
    if let newStartMillis = newStartMillis {
      let target = Date(timeIntervalSince1970: TimeInterval(newStartMillis) / 1000.0)
      let reference: Date
      if let timestamp = timestamp {
        reference = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
      } else {
        reference = foundEvent.startDate
      }
      guard let shifted = shiftStart(
        foundEvent.startDate,
        reference: reference,
        to: target,
        isAllDay: effectiveIsAllDay,
        timeZone: foundEvent.timeZone ?? .current
      ) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.operationFailed,
          message: "Could not apply the new start to the event"
        )))
        return
      }
      newStart = shifted
    }

    var parsedRecurrenceRule: EKRecurrenceRule?
    if !patch.clearedFields.contains("recurrenceRule"), let rruleString = recurrenceRule {
      guard let rule = parseRecurrenceRule(rruleString) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "Invalid recurrence rule: \(rruleString)"
        )))
        return
      }
      parsedRecurrenceRule = rule
    }

    // Apply field changes.
    patch.apply(to: foundEvent)

    // Apply time-of-day and/or duration changes. The existing date is
    // preserved; only the time component is replaced.
    if newStart != nil || durationMinutes != nil {
      let duration = durationMinutes.map { TimeInterval($0 * 60) }
        ?? foundEvent.endDate.timeIntervalSince(foundEvent.startDate)
      let start: Date = newStart ?? foundEvent.startDate
      foundEvent.startDate = start
      foundEvent.endDate = start.addingTimeInterval(duration)
    }

    patch.applyTimeZone(to: foundEvent)

    // Clearing the rule on a `thisAndFollowing` split is the one case EventKit
    // gets wrong natively (it collapses the whole series), so it splits the
    // series by hand rather than through the shared save below — mirror
    // Android's dedicated `updateRecurringThisAndFollowing` (#93).
    if span == "thisAndFollowing",
       patch.clearedFields.contains("recurrenceRule"),
       let timestamp = timestamp {
      detachThisAndFollowing(
        occurrence: foundEvent,
        eventId: eventId,
        occurrenceDate: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
        completion: completion
      )
      return
    }

    // Apply the recurrence-rule patch.
    if patch.clearedFields.contains("recurrenceRule") {
      foundEvent.recurrenceRules = nil
    } else if let rule = parsedRecurrenceRule {
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

  /// Deletes a recurring event's series, choosing which occurrences are
  /// removed.
  ///
  /// `span` is "allEvents" (the whole series) or "thisAndFollowing" (the
  /// occurrence at `timestamp` and every later one). Single-occurrence
  /// deletes go through `deleteEvent` with a timestamp.
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

    // Both spans remove with .futureEvents: from the master that removes the
    // whole series; from an occurrence it removes that occurrence and every
    // later one. (.futureEvents on a non-recurring event behaves like
    // .thisEvent.)
    do {
      try eventStore.remove(foundEvent, span: .futureEvents)
      completion(.success(()))
    } catch {
      completion(.failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Failed to delete recurring event: \(error.localizedDescription)"
      )))
    }
  }
}
