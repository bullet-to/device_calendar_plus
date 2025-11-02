import Flutter
import UIKit
import EventKit

public class DeviceCalendarPlusIosPlugin: NSObject, FlutterPlugin {
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
    case "retrieveEvents":
      handleRetrieveEvents(call: call, result: result)
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
}
