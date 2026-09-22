import EventKit
import Foundation

enum CalendarPermissionType {
  case write  // Need to write events (iOS 17+ writeOnly or fullAccess is fine)
  case full   // Need to read calendars/events (requires fullAccess)
}

/// The calendar access this app holds, normalised across iOS versions.
/// EventKit's own `EKAuthorizationStatus` means different things on either side
/// of iOS 17 (`.authorized` there is full access; `.writeOnly` does not exist),
/// and the `CalendarAuthorization` seam flattens that away.
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
  /// `supportsWriteOnly` alone decides which mapping applies, so a test can
  /// drive the pre-17 mapping from a modern simulator. The `#available` below
  /// is the compiler's requirement for naming the iOS 17+ cases, not a second
  /// source of truth.
  ///
  /// - Parameter supportsWriteOnly: whether this OS has the iOS 17+ tiers.
  ///   Where it does not, only `.authorized` exists and it means full access.
  init(ekStatus: EKAuthorizationStatus, supportsWriteOnly: Bool) {
    guard supportsWriteOnly else {
      self.init(legacyEkStatus: ekStatus)
      return
    }
    guard #available(iOS 17.0, *) else {
      // Unreachable: `supportsWriteOnly` can only be true on iOS 17+, since
      // `EventKitAuthorization` derives it from this same `#available` and no
      // other implementation reaches here. The compiler still needs a branch.
      self.init(legacyEkStatus: ekStatus)
      return
    }

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
  }

  /// iOS 16 and below: only `.authorized` exists, and it means full access.
  private init(legacyEkStatus ekStatus: EKAuthorizationStatus) {
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

  /// The tier lattice, read off `rank` rather than restated: full access covers
  /// everything, a write-only grant covers writes but never reads. Adding a
  /// tier means adding one `rank` row and nothing else.
  func satisfies(_ required: CalendarPermissionType) -> Bool {
    rank >= CalendarAccess(granted: required).rank
  }

  /// Can't be changed from inside the app — the user must use Settings.
  var isTerminal: Bool { self == .denied || self == .restricted }

  /// How much access this value represents, as a total order. Everything short
  /// of a grant ranks the same: `.notDetermined`, `.denied` and `.restricted`
  /// are different reasons for the same amount of access — none.
  var rank: Int {
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
  /// these by name, so they are contract rather than display strings.
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
