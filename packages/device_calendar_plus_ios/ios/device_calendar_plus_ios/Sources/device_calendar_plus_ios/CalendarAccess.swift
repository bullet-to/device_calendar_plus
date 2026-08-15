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

  /// The tier lattice, defined once: full access covers everything, a
  /// write-only grant covers writes but never reads.
  func satisfies(_ required: CalendarPermissionType) -> Bool {
    switch required {
    case .full:
      return self == .fullAccess
    case .write:
      return self == .fullAccess || self == .writeOnly
    }
  }

  /// Can't be changed from inside the app — the user must use Settings.
  var isTerminal: Bool { self == .denied || self == .restricted }

  /// How much access this value represents. A total order, so "supersedes" is
  /// a fact about the type rather than a rule some caller has to remember.
  /// `.denied` and `.restricted` share a rank: they are different reasons for
  /// the same amount of access, and neither can displace the other.
  private var rank: Int {
    switch self {
    case .notDetermined:
      return 0
    case .denied, .restricted:
      return 1
    case .writeOnly:
      return 2
    case .fullAccess:
      return 3
    }
  }

  /// Whether this answer represents strictly more access than `other`, where
  /// `nil` means "no answer yet". `AccessRecord` uses it to only ever move up,
  /// so a refused *full* upgrade can never erase the write-only grant behind it.
  func supersedes(_ other: CalendarAccess?) -> Bool {
    rank > (other?.rank ?? 0)
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
