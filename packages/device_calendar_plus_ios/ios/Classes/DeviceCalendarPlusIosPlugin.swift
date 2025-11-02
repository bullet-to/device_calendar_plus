import Flutter
import UIKit
import EventKit

public class DeviceCalendarPlusIosPlugin: NSObject, FlutterPlugin {
  // Permission status codes matching CalendarPermissionStatus enum
  private static let statusGranted = 0
  private static let statusWriteOnly = 1
  private static let statusDenied = 2
  private static let statusRestricted = 3
  private static let statusNotDetermined = 4
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "device_calendar_plus_ios", binaryMessenger: registrar.messenger())
    let instance = DeviceCalendarPlusIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "requestPermissions":
      requestCalendarPermissions(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func requestCalendarPermissions(result: @escaping FlutterResult) {
    // Check if required Info.plist keys are present
    let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCalendarsUsageDescription") as? String
    
    if usageDescription == nil || usageDescription?.isEmpty == true {
      var errorMessage = "Calendar usage description not declared in Info.plist.\n\n"
      errorMessage += "Add the following to ios/Runner/Info.plist:\n"
      errorMessage += "<key>NSCalendarsUsageDescription</key>\n"
      errorMessage += "<string>Access your calendar to view and manage events.</string>\n"
      
      if #available(iOS 17.0, *) {
        errorMessage += "<key>NSCalendarsWriteOnlyAccessUsageDescription</key>\n"
        errorMessage += "<string>Add events without reading existing events.</string>"
      }
      
      // Error code must match PlatformExceptionCodes.permissionsNotDeclared
      result(FlutterError(code: "PERMISSIONS_NOT_DECLARED", message: errorMessage, details: nil))
      return
    }
    
    let eventStore = EKEventStore()
    
    if #available(iOS 17.0, *) {
      // iOS 17+ has separate read and write access
      let currentStatus = EKEventStore.authorizationStatus(for: .event)
      
      switch currentStatus {
      case .fullAccess:
        result(DeviceCalendarPlusIosPlugin.statusGranted)
        return
      case .writeOnly:
        result(DeviceCalendarPlusIosPlugin.statusWriteOnly)
        return
      case .denied:
        result(DeviceCalendarPlusIosPlugin.statusDenied)
        return
      case .restricted:
        result(DeviceCalendarPlusIosPlugin.statusRestricted)
        return
      case .notDetermined:
        // Request full access
        eventStore.requestFullAccessToEvents { granted, error in
          DispatchQueue.main.async {
            if granted {
              result(DeviceCalendarPlusIosPlugin.statusGranted)
            } else {
              result(DeviceCalendarPlusIosPlugin.statusDenied)
            }
          }
        }
      @unknown default:
        result(DeviceCalendarPlusIosPlugin.statusDenied)
      }
    } else {
      // iOS 16 and below
      let currentStatus = EKEventStore.authorizationStatus(for: .event)
      
      switch currentStatus {
      case .authorized:
        result(DeviceCalendarPlusIosPlugin.statusGranted)
        return
      case .denied:
        result(DeviceCalendarPlusIosPlugin.statusDenied)
        return
      case .restricted:
        result(DeviceCalendarPlusIosPlugin.statusRestricted)
        return
      case .notDetermined:
        eventStore.requestAccess(to: .event) { granted, error in
          DispatchQueue.main.async {
            if granted {
              result(DeviceCalendarPlusIosPlugin.statusGranted)
            } else {
              result(DeviceCalendarPlusIosPlugin.statusDenied)
            }
          }
        }
      @unknown default:
        result(DeviceCalendarPlusIosPlugin.statusDenied)
      }
    }
  }
}
