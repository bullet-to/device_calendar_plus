import Flutter
import UIKit
import EventKit

public class DeviceCalendarPlusIosPlugin: NSObject, FlutterPlugin {
  private let eventStore = EKEventStore()
  private lazy var permissionService = PermissionService(eventStore: eventStore)
  private lazy var calendarService = CalendarService(eventStore: eventStore, permissionService: permissionService)
  
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
}
