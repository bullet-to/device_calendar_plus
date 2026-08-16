import EventKit
import Foundation

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

/// The calendar access this app holds, normalised across iOS versions.
///
/// EventKit's own `EKAuthorizationStatus` means different things on either
/// side of iOS 17 (`.authorized` there is full access; `.writeOnly` does not
/// exist). The `CalendarAuthorization` seam flattens that away, so nothing
/// above it has to ask what OS it is on.
enum CalendarAccess {
  case notDetermined
  case denied
  case restricted
  case writeOnly
  case fullAccess

  init(granted type: CalendarPermissionType) {
    switch type {
    case .full:
      self = .fullAccess
    case .write:
      self = .writeOnly
    }
  }

  /// Normalises EventKit's own status across the iOS 17 divide.
  ///
  /// Pure, and branches on `supportsWriteOnly` rather than on `#available`, so
  /// a test can drive the pre-17 mapping from a modern simulator — the OS
  /// version is a fact handed in by the `CalendarAuthorization` seam, not
  /// something this mapping asks the runtime.
  ///
  /// - Parameter supportsWriteOnly: whether this OS has the iOS 17+ tiers.
  ///   Where it does not, only `.authorized` exists and it means full access.
  init(ekStatus: EKAuthorizationStatus, supportsWriteOnly: Bool) {
    if #available(iOS 17.0, *), supportsWriteOnly {
      switch ekStatus {
      case .fullAccess:
        self = .fullAccess
      case .writeOnly:
        self = .writeOnly
      case .denied:
        self = .denied
      case .restricted:
        self = .restricted
      case .notDetermined:
        self = .notDetermined
      @unknown default:
        self = .denied
      }
      return
    }

    // iOS 16 and below only has .authorized, which is full access.
    switch ekStatus {
    case .authorized:
      self = .fullAccess
    case .denied:
      self = .denied
    case .restricted:
      self = .restricted
    case .notDetermined:
      self = .notDetermined
    // Not `@unknown default`: the iOS 17+ `.writeOnly` case is unreachable on
    // an OS without the tier but still counts against exhaustiveness, and a
    // plain `default` maps it to the same `.denied` without the warning.
    default:
      self = .denied
    }
  }

  /// The tier lattice, read off `rank` rather than restated: full access
  /// covers everything, a write-only grant covers writes but never reads.
  /// Expressed in terms of the grant the requirement asks for, so adding a
  /// tier means adding one `rank` row and nothing else.
  func satisfies(_ required: CalendarPermissionType) -> Bool {
    rank >= CalendarAccess(granted: required).rank
  }

  /// Can't be changed from inside the app — the user must use Settings.
  var isTerminal: Bool { self == .denied || self == .restricted }

  /// How much access this value represents, as a total order, so `satisfies` is
  /// a fact about the type rather than a rule some caller has to remember.
  /// Everything short of a grant ranks the same: `.notDetermined`, `.denied`
  /// and `.restricted` are different reasons for the same amount of access —
  /// none.
  private var rank: Int {
    switch self {
    case .notDetermined, .denied, .restricted:
      return 0
    case .writeOnly:
      return 1
    case .fullAccess:
      return 2
    }
  }

  /// The method-channel wire format: Dart's `CalendarPermissionStatus` parses
  /// these by name, so they are contract rather than display strings. Used only
  /// at the channel boundary, and defined only here.
  var wireValue: String {
    switch self {
    case .fullAccess:
      return "granted"
    case .writeOnly:
      return "writeOnly"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    }
  }
}
