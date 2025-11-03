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
    case "listCalendars":
      handleListCalendars(result: result)
    case "createCalendar":
      handleCreateCalendar(call: call, result: result)
    case "updateCalendar":
      handleUpdateCalendar(call: call, result: result)
    case "deleteCalendar":
      handleDeleteCalendar(call: call, result: result)
    case "retrieveEvents":
      handleRetrieveEvents(call: call, result: result)
    case "getEvent":
      handleGetEvent(call: call, result: result)
    case "showEvent":
      handleShowEvent(call: call, result: result)
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
  
  private func handleRetrieveEvents(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for retrieveEvents",
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
  
  private func handleShowEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: PlatformExceptionCodes.invalidArguments,
        message: "Invalid arguments for showEvent",
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
              result(FlutterError(
                code: PlatformExceptionCodes.unknownError,
                message: "Failed to get root view controller",
                details: nil
              ))
              return
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
