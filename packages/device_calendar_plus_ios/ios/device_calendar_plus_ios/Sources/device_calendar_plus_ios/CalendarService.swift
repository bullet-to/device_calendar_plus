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
      // Google/Exchange (and other non-iCloud) sources reject new calendars with
      // EKError 500. Reject early with a clear error rather than letting
      // saveCalendar throw an opaque "operation failed".
      guard sourceSupportsCreation(found) else {
        completion(.failure(CalendarError(
          code: PlatformExceptionCodes.readOnly,
          message: "Source '\(found.title)' does not allow calendars to be created. "
            + "Use iCloud or the local source."
        )))
        return
      }
      source = found
    } else {
      // No sourceId provided — prefer iCloud (syncs across devices), then local.
      let icloud = eventStore.sources.first(where: {
        $0.sourceType == .calDAV && $0.title.lowercased() == "icloud"
      })
      let local = eventStore.sources.first(where: { $0.sourceType == .local })
      guard let fallback = icloud ?? local else {
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
    
    let calendar: EKCalendar
    switch writableCalendar(calendarId) {
    case .failure(let error):
      completion(.failure(error))
      return
    case .success(let found):
      calendar = found
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
    
    let calendar: EKCalendar
    switch writableCalendar(calendarId) {
    case .failure(let error):
      completion(.failure(error))
      return
    case .success(let found):
      calendar = found
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
        "supportsCalendarCreation": sourceSupportsCreation(source),
      ]
    }

    completion(.success(sources))
  }

  /// The calendar a rename, recolor or delete may act on: looked up by ID,
  /// then refused if EventKit won't let the app touch it. The one place that
  /// defines "a calendar we may mutate" on iOS, as `writeRefusal` is on
  /// Android.
  private func writableCalendar(_ calendarId: String) -> Result<EKCalendar, CalendarError> {
    guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
      return .failure(CalendarError(
        code: PlatformExceptionCodes.notFound,
        message: "Calendar with ID \(calendarId) not found"
      ))
    }
    if let refusal = readOnlyRefusal(calendar) {
      return .failure(refusal)
    }
    return .success(calendar)
  }

  /// The readOnly refusal for a calendar the app can't rename, recolor or
  /// delete, decided before EventKit is asked so the caller gets `readOnly`
  /// rather than the opaque `operationFailed` a thrown save would become
  /// (#126).
  ///
  /// Two EventKit flags feed it. `allowsContentModifications == false` is what
  /// `listCalendars` reports as `readOnly`, so every calendar the list calls
  /// read-only is refused. `isImmutable` is EventKit's own "cannot be edited
  /// or deleted" flag; it says nothing about adding events, so a calendar can
  /// be immutable yet listed as writable (an account's default calendar,
  /// say). Those are refused too — deliberately, so don't "simplify" this to
  /// `allowsContentModifications` alone. The refusal set is therefore a
  /// superset of the list's `readOnly`; `doc/calendars.md` owns the wording.
  ///
  /// Pure so that immutable-yet-writable cell can be pinned in
  /// `RunnerTests/CalendarServiceTests.swift`: Dart never sees `isImmutable`,
  /// so no on-device test can pick such a calendar, and a test can't build an
  /// `EKCalendar` with the flag set.
  static func readOnlyRefusal(
    isImmutable: Bool, allowsContentModifications: Bool, title: String
  ) -> CalendarError? {
    guard isImmutable || !allowsContentModifications else {
      return nil
    }
    return CalendarError(
      code: PlatformExceptionCodes.readOnly,
      message: "Calendar '\(title)' is read-only and cannot be modified or deleted"
    )
  }

  private func readOnlyRefusal(_ calendar: EKCalendar) -> CalendarError? {
    return CalendarService.readOnlyRefusal(
      isImmutable: calendar.isImmutable,
      allowsContentModifications: calendar.allowsContentModifications,
      title: calendar.title)
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

  private func sourceSupportsCreation(_ source: EKSource) -> Bool {
    switch source.sourceType {
    case .local: return true
    case .calDAV: return source.title.lowercased() == "icloud"
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

