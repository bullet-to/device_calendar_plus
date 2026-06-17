import Flutter
import UIKit
import EventKit
import EventKitUI

public class DeviceCalendarPlusIosPlugin: NSObject, FlutterPlugin, EKEventViewDelegate, EKEventEditViewDelegate {
  private let eventStore = EKEventStore()
  private lazy var permissionService = PermissionService(eventStore: eventStore)
  private lazy var calendarService = CalendarService(eventStore: eventStore, permissionService: permissionService)
  private lazy var eventsService = EventsService(eventStore: eventStore, permissionService: permissionService)
  private var eventModalResult: FlutterResult?
  private var createEventModalResult: FlutterResult?

  /// Serial queue for EventKit data operations. EventKit calls block the
  /// calling thread (listEvents fans out across the store, create/update/delete
  /// touch the calendar database), and method-channel handlers run on the main
  /// thread, so query-heavy calls jank the UI there (#181). A single serial
  /// queue keeps the data operations in call order and serializes them against
  /// each other, mirroring the Android plugin's single-thread provider
  /// executor. The permission and modal handlers deliberately stay on the main
  /// thread — they're light and must touch UIKit — so the `eventStore` they
  /// reach is not serialized against this queue. That's the same boundary
  /// Android draws; in practice those paths are user-driven and don't overlap a
  /// bulk data operation.
  private let providerQueue = DispatchQueue(label: "to.bullet.device_calendar_plus.provider")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "device_calendar_plus_ios", binaryMessenger: registrar.messenger())
    let instance = DeviceCalendarPlusIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermissions":
      handleRequestPermissions(call: call, result: result)
    case "hasPermissions":
      handleHasPermissions(result: result)
    case "openAppSettings":
      handleOpenAppSettings(result: result)
    case "listCalendars":
      handleListCalendars(result: result)
    case "listSources":
      handleListSources(result: result)
    case "createCalendar":
      handleCreateCalendar(call: call, result: result)
    case "updateCalendar":
      handleUpdateCalendar(call: call, result: result)
    case "deleteCalendar":
      handleDeleteCalendar(call: call, result: result)
    case "listEvents":
      handleListEvents(call: call, result: result)
    case "getEvent":
      handleGetEvent(call: call, result: result)
    case "showEventModal":
      handleShowEventModal(call: call, result: result)
    case "showCreateEventModal":
      handleShowCreateEventModal(call: call, result: result)
    case "createEvent":
      handleCreateEvent(call: call, result: result)
    case "deleteEvent":
      handleDeleteEvent(call: call, result: result)
    case "updateEvent":
      handleUpdateEvent(call: call, result: result)
    case "updateRecurring":
      handleUpdateRecurring(call: call, result: result)
    case "deleteRecurring":
      handleDeleteRecurring(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Runs an EventKit service call on the serial provider queue (off the main
  /// thread — see `providerQueue`) and delivers its Result back on the main
  /// thread, mapping `CalendarError` to `FlutterError`. Callers parse and
  /// validate arguments on the main thread first, then hand the service call
  /// here so the threading contract lives in exactly one place.
  private func runOnProvider<T>(
    _ result: @escaping FlutterResult,
    _ work: @escaping (@escaping (Result<T, CalendarError>) -> Void) -> Void
  ) {
    providerQueue.async {
      work { serviceResult in
        DispatchQueue.main.async {
          switch serviceResult {
          case .success(let value):
            result(value)
          case .failure(let error):
            result(FlutterError(code: error.code, message: error.message, details: nil))
          }
        }
      }
    }
  }

  /// `Void`-success overload of `runOnProvider`. Swift resolves to this for
  /// `Result<Void, CalendarError>` service calls, replying `nil` on success.
  private func runOnProvider(
    _ result: @escaping FlutterResult,
    _ work: @escaping (@escaping (Result<Void, CalendarError>) -> Void) -> Void
  ) {
    providerQueue.async {
      work { serviceResult in
        DispatchQueue.main.async {
          switch serviceResult {
          case .success:
            result(nil)
          case .failure(let error):
            result(FlutterError(code: error.code, message: error.message, details: nil))
          }
        }
      }
    }
  }

  private func handleRequestPermissions(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let writeOnly = (args?["writeOnly"] as? Bool) ?? false
    permissionService.requestPermissions(writeOnly: writeOnly) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let status):
          result(status)
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
    }
  }
  
  private func handleHasPermissions(result: @escaping FlutterResult) {
    let serviceResult = permissionService.hasPermissions()
    switch serviceResult {
    case .success(let status):
      result(status)
    case .failure(let error):
      result(FlutterError(code: error.code, message: error.message, details: nil))
    }
  }
  
  private func handleOpenAppSettings(result: @escaping FlutterResult) {
    guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
      result(FlutterError(
        code: PlatformExceptionCodes.unknownError,
        message: "Failed to create settings URL",
        details: nil
      ))
      return
    }
    
    if UIApplication.shared.canOpenURL(settingsUrl) {
      UIApplication.shared.open(settingsUrl, options: [:]) { success in
        if success {
          result(nil)
        } else {
          result(FlutterError(
            code: PlatformExceptionCodes.unknownError,
            message: "Failed to open app settings",
            details: nil
          ))
        }
      }
    } else {
      result(FlutterError(
        code: PlatformExceptionCodes.unknownError,
        message: "Cannot open settings URL",
        details: nil
      ))
    }
  }
  
  private func handleListCalendars(result: @escaping FlutterResult) {
    runOnProvider(result) { self.calendarService.listCalendars(completion: $0) }
  }

  private func handleListSources(result: @escaping FlutterResult) {
    runOnProvider(result) { self.calendarService.listSources(completion: $0) }
  }

  private func handleCreateCalendar(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for createCalendar",
        details: nil
      ))
      return
    }

    // Parse name (required)
    guard let name = args["name"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid name",
        details: nil
      ))
      return
    }

    // Parse colorHex (optional)
    let colorHex = args["colorHex"] as? String

    // Parse sourceId (optional — if nil, uses tiered fallback)
    let sourceId = args["sourceId"] as? String

    runOnProvider(result) {
      self.calendarService.createCalendar(
        name: name, colorHex: colorHex, sourceId: sourceId, completion: $0)
    }
  }
  
  private func handleUpdateCalendar(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for updateCalendar",
        details: nil
      ))
      return
    }
    
    // Parse calendar ID (required)
    guard let calendarId = args["calendarId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid calendarId",
        details: nil
      ))
      return
    }
    
    // Parse name (optional)
    let name = args["name"] as? String
    
    // Parse colorHex (optional)
    let colorHex = args["colorHex"] as? String
    
    runOnProvider(result) {
      self.calendarService.updateCalendar(
        calendarId: calendarId, name: name, colorHex: colorHex, completion: $0)
    }
  }
  
  private func handleDeleteCalendar(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for deleteCalendar",
        details: nil
      ))
      return
    }
    
    // Parse calendar ID (required)
    guard let calendarId = args["calendarId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid calendarId",
        details: nil
      ))
      return
    }
    
    runOnProvider(result) {
      self.calendarService.deleteCalendar(calendarId: calendarId, completion: $0)
    }
  }
  
  private func handleListEvents(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for listEvents",
        details: nil
      ))
      return
    }
    
    // Parse start date
    guard let startDateMillis = args["startDate"] as? Int64 else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid startDate",
        details: nil
      ))
      return
    }
    
    // Parse end date
    guard let endDateMillis = args["endDate"] as? Int64 else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid endDate",
        details: nil
      ))
      return
    }
    
    // Convert milliseconds to Date
    let startDate = Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000.0)
    let endDate = Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000.0)
    
    // Parse calendar IDs (optional)
    let calendarIds = args["calendarIds"] as? [String]
    
    runOnProvider(result) {
      self.eventsService.retrieveEvents(
        startDate: startDate, endDate: endDate, calendarIds: calendarIds, completion: $0)
    }
  }
  
  private func handleGetEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for getEvent",
        details: nil
      ))
      return
    }
    
    // Parse event ID (required)
    guard let eventId = args["eventId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid eventId",
        details: nil
      ))
      return
    }
    
    // Parse timestamp (optional, for recurring events)
    let timestamp = args["timestamp"] as? Int64
    
    runOnProvider(result) {
      self.eventsService.getEvent(eventId: eventId, timestamp: timestamp, completion: $0)
    }
  }
  
  private func handleShowEventModal(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for showEventModal",
        details: nil
      ))
      return
    }
    
    // Parse event ID (required)
    guard let eventId = args["eventId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid eventId",
        details: nil
      ))
      return
    }
    
    // Parse timestamp (optional, for recurring events)
    let timestamp = args["timestamp"] as? Int64
    let edit = args["edit"] as? Bool ?? false

    eventsService.showEvent(eventId: eventId, timestamp: timestamp, edit: edit) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let viewController):
          if let viewController = viewController {
            guard let rootViewController = self.getRootViewController() else {
              fatalError("Failed to get root view controller - plugin lifecycle error")
            }

            // Set the appropriate delegate based on view controller type
            if let editVC = viewController as? EKEventEditViewController {
              editVC.editViewDelegate = self
            } else if let viewVC = viewController as? EKEventViewController {
              viewVC.delegate = self
            }

            self.eventModalResult = result

            // EKEventEditViewController is itself a UINavigationController subclass,
            // so present it directly. EKEventViewController needs wrapping in a
            // navigation controller for its action buttons and dismissal to work.
            let presentedViewController: UIViewController
            if let navigationController = viewController as? UINavigationController {
              presentedViewController = navigationController
            } else {
              presentedViewController = UINavigationController(rootViewController: viewController)
            }
            presentedViewController.modalPresentationStyle = .pageSheet

            rootViewController.present(presentedViewController, animated: true, completion: nil)
          } else {
            result(nil)
          }
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
    }
  }
  
  private func handleShowCreateEventModal(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    eventsService.createEventForModal(
      title: args["title"] as? String,
      startDate: args["startDate"] as? Int64,
      endDate: args["endDate"] as? Int64,
      description: args["description"] as? String,
      location: args["location"] as? String,
      isAllDay: args["isAllDay"] as? Bool,
      recurrenceRule: args["recurrenceRule"] as? String,
      availability: args["availability"] as? String
    ) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let event):
          guard let rootViewController = self.getRootViewController() else {
            fatalError("Failed to get root view controller - plugin lifecycle error")
          }

          let editViewController = EKEventEditViewController()
          editViewController.eventStore = self.eventStore
          editViewController.event = event // nil = blank editor
          editViewController.editViewDelegate = self

          self.createEventModalResult = result
          rootViewController.present(editViewController, animated: true, completion: nil)

        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
    }
  }

  private func handleCreateEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for createEvent",
        details: nil
      ))
      return
    }
    
    // Parse required parameters
    guard let title = args["title"] as? String,
          let startDateMillis = args["startDate"] as? Int64,
          let endDateMillis = args["endDate"] as? Int64,
          let isAllDay = args["isAllDay"] as? Bool,
          let availability = args["availability"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing required arguments for createEvent",
        details: nil
      ))
      return
    }

    // Parse optional parameters
    // calendarId is optional: nil routes the event to the default calendar.
    let calendarId = args["calendarId"] as? String
    let description = args["description"] as? String
    let location = args["location"] as? String
    let url = args["url"] as? String
    let timeZone = args["timeZone"] as? String
    let recurrenceRule = args["recurrenceRule"] as? String
    // Reminders: minutes before start (already normalized by the Dart layer).
    let reminders = args["reminders"] as? [Int]

    // Convert dates
    let startDate = Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000.0)
    let endDate = Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000.0)

    runOnProvider(result) {
      self.eventsService.createEvent(
        calendarId: calendarId,
        title: title,
        startDate: startDate,
        endDate: endDate,
        isAllDay: isAllDay,
        description: description,
        location: location,
        url: url,
        timeZone: timeZone,
        availability: availability,
        recurrenceRule: recurrenceRule,
        reminders: reminders,
        completion: $0)
    }
  }
  
  private func handleDeleteEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for deleteEvent",
        details: nil
      ))
      return
    }
    
    // Parse event ID (required)
    guard let eventId = args["eventId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid eventId",
        details: nil
      ))
      return
    }
    
    let timestamp = args["timestamp"] as? Int64

    runOnProvider(result) {
      self.eventsService.deleteEvent(eventId: eventId, timestamp: timestamp, completion: $0)
    }
  }
  
  private func handleUpdateEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for updateEvent",
        details: nil
      ))
      return
    }
    
    // Parse event ID (required)
    guard let eventId = args["eventId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid eventId",
        details: nil
      ))
      return
    }
    
    // Parse optional parameters
    let timestamp = args["timestamp"] as? Int64
    let startDate = (args["startDate"] as? Int64).map {
      Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
    }
    let endDate = (args["endDate"] as? Int64).map {
      Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
    }

    let patch = EventFieldPatch(args: args)
    runOnProvider(result) {
      self.eventsService.updateEvent(
        eventId: eventId,
        timestamp: timestamp,
        startDate: startDate,
        endDate: endDate,
        patch: patch,
        completion: $0)
    }
  }
  
  private func handleUpdateRecurring(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for updateRecurring",
        details: nil
      ))
      return
    }

    // Parse event ID (required)
    guard let eventId = args["eventId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid eventId",
        details: nil
      ))
      return
    }

    // Parse span (required)
    guard let span = args["span"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid span",
        details: nil
      ))
      return
    }

    // Parse optional parameters
    let timestamp = args["timestamp"] as? Int64
    let newStartMillis = args["newStartMillis"] as? Int64
    let durationMinutes = args["durationMinutes"] as? Int
    let recurrenceRule = args["recurrenceRule"] as? String

    let patch = EventFieldPatch(args: args)
    runOnProvider(result) {
      self.eventsService.updateRecurring(
        eventId: eventId,
        timestamp: timestamp,
        span: span,
        newStartMillis: newStartMillis,
        durationMinutes: durationMinutes,
        recurrenceRule: recurrenceRule,
        patch: patch,
        completion: $0)
    }
  }

  private func handleDeleteRecurring(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for deleteRecurring",
        details: nil
      ))
      return
    }

    // Parse event ID (required)
    guard let eventId = args["eventId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid eventId",
        details: nil
      ))
      return
    }

    // Parse span (required)
    guard let span = args["span"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid span",
        details: nil
      ))
      return
    }

    let timestamp = args["timestamp"] as? Int64

    runOnProvider(result) {
      self.eventsService.deleteRecurring(
        eventId: eventId, timestamp: timestamp, span: span, completion: $0)
    }
  }

  // MARK: - EKEventViewControllerDelegate
  
  public func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
    // Dismiss the modal
    controller.navigationController?.dismiss(animated: true) {
      // Call the stored result callback after modal is dismissed
      self.eventModalResult?(nil)
      self.eventModalResult = nil
    }
  }
  
  // MARK: - EKEventEditViewDelegate

  public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
    controller.dismiss(animated: true) {
      // Resolve whichever result callback is active (create modal or edit modal)
      if self.createEventModalResult != nil {
        self.createEventModalResult?(nil)
        self.createEventModalResult = nil
      } else {
        self.eventModalResult?(nil)
        self.eventModalResult = nil
      }
    }
  }

  // MARK: - Helper Methods
  
  private func getRootViewController() -> UIViewController? {
    // Get the key window
    if #available(iOS 13.0, *) {
      // Use window scene for iOS 13+
      let scenes = UIApplication.shared.connectedScenes
      let windowScene = scenes.first as? UIWindowScene
      return windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    } else {
      // Use deprecated keyWindow for older iOS versions
      return UIApplication.shared.keyWindow?.rootViewController
    }
  }
}
