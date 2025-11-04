import Flutter
import UIKit
import EventKit
import EventKitUI

public class DeviceCalendarPlusIosPlugin: NSObject, FlutterPlugin, EKEventViewDelegate {
  private let eventStore = EKEventStore()
  private lazy var permissionService = PermissionService(eventStore: eventStore)
  private lazy var calendarService = CalendarService(eventStore: eventStore, permissionService: permissionService)
  private lazy var eventsService = EventsService(eventStore: eventStore, permissionService: permissionService)
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "device_calendar_plus_ios", binaryMessenger: registrar.messenger())
    let instance = DeviceCalendarPlusIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      handleGetPlatformVersion(result: result)
    case "requestPermissions":
      handleRequestPermissions(result: result)
    case "hasPermissions":
      handleHasPermissions(result: result)
    case "openAppSettings":
      handleOpenAppSettings(result: result)
    case "listCalendars":
      handleListCalendars(result: result)
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
    case "createEvent":
      handleCreateEvent(call: call, result: result)
    case "deleteEvent":
      handleDeleteEvent(call: call, result: result)
    case "updateEvent":
      handleUpdateEvent(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func handleGetPlatformVersion(result: @escaping FlutterResult) {
    result("iOS " + UIDevice.current.systemVersion)
  }
  
  private func handleRequestPermissions(result: @escaping FlutterResult) {
    permissionService.requestPermissions { serviceResult in
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
    calendarService.listCalendars { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let calendars):
          result(calendars)
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
    }
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
    
    calendarService.createCalendar(name: name, colorHex: colorHex) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let calendarId):
          result(calendarId)
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
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
    
    calendarService.updateCalendar(calendarId: calendarId, name: name, colorHex: colorHex) { serviceResult in
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
    
    calendarService.deleteCalendar(calendarId: calendarId) { serviceResult in
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
    
    eventsService.retrieveEvents(
      startDate: startDate,
      endDate: endDate,
      calendarIds: calendarIds
    ) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let events):
          result(events)
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
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
    
    // Parse instance ID
    guard let instanceId = args["instanceId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid instanceId",
        details: nil
      ))
      return
    }
    
    eventsService.getEvent(instanceId: instanceId) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let event):
          result(event)
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
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
    
    // Parse instance ID
    guard let instanceId = args["instanceId"] as? String else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing or invalid instanceId",
        details: nil
      ))
      return
    }
    
    eventsService.showEvent(instanceId: instanceId) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let viewController):
          // If we have a view controller (modal mode), present it
          if let viewController = viewController {
            // Get the root view controller
            guard let rootViewController = self.getRootViewController() else {
              fatalError("Failed to get root view controller - plugin lifecycle error")
            }
            
            // Set the delegate
            viewController.delegate = self
            
            // Wrap in navigation controller for proper dismissal
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .pageSheet
            
            rootViewController.present(navigationController, animated: true) {
              result(nil)
            }
          } else {
            // Calendar app was opened
            result(nil)
          }
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
    guard let calendarId = args["calendarId"] as? String,
          let title = args["title"] as? String,
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
    let description = args["description"] as? String
    let location = args["location"] as? String
    let timeZone = args["timeZone"] as? String
    
    // Convert dates
    let startDate = Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000.0)
    let endDate = Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000.0)
    
    eventsService.createEvent(
      calendarId: calendarId,
      title: title,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      description: description,
      location: location,
      timeZone: timeZone,
      availability: availability
    ) { serviceResult in
      DispatchQueue.main.async {
        switch serviceResult {
        case .success(let eventId):
          result(eventId)
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
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
    
    // Parse parameters
    guard let instanceId = args["instanceId"] as? String,
          let deleteAllInstances = args["deleteAllInstances"] as? Bool else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing required arguments for deleteEvent",
        details: nil
      ))
      return
    }
    
    eventsService.deleteEvent(
      instanceId: instanceId,
      deleteAllInstances: deleteAllInstances
    ) { serviceResult in
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
  
  private func handleUpdateEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for updateEvent",
        details: nil
      ))
      return
    }
    
    // Parse required parameters
    guard let instanceId = args["instanceId"] as? String,
          let updateAllInstances = args["updateAllInstances"] as? Bool else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Missing required arguments for updateEvent",
        details: nil
      ))
      return
    }
    
    // Parse optional parameters
    let title = args["title"] as? String
    let description = args["description"] as? String
    let location = args["location"] as? String
    let isAllDay = args["isAllDay"] as? Bool
    let timeZone = args["timeZone"] as? String
    
    // Parse dates if provided
    let startDate: Date?
    if let startDateMillis = args["startDate"] as? Int64 {
      startDate = Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000.0)
    } else {
      startDate = nil
    }
    
    let endDate: Date?
    if let endDateMillis = args["endDate"] as? Int64 {
      endDate = Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000.0)
    } else {
      endDate = nil
    }
    
    eventsService.updateEvent(
      instanceId: instanceId,
      updateAllInstances: updateAllInstances,
      title: title,
      startDate: startDate,
      endDate: endDate,
      description: description,
      location: location,
      isAllDay: isAllDay,
      timeZone: timeZone
    ) { serviceResult in
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
  
  // MARK: - EKEventViewControllerDelegate
  
  public func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
    // Dismiss the modal
    controller.navigationController?.dismiss(animated: true, completion: nil)
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
