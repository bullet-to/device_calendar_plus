import EventKit
import Foundation

/// The OS-level calendar authorization seam.
///
/// Injected into `PermissionService` so tests can drive the whole grant path
/// — on either side of the iOS 17 divide — without a real system prompt. The
/// caller picks the tier: deciding which tier an ask resolves to is policy,
/// and policy lives in `PermissionService`, leaving implementations to do
/// nothing but report the OS's capabilities and dispatch to it.
protocol CalendarAuthorization {
  /// Whether this OS has the iOS 17+ write-only tier at all. The only version
  /// question `PermissionService` asks, and it asks it of the seam, so the
  /// pre-17 world is a test fixture rather than a runtime accident.
  var supportsWriteOnly: Bool { get }

  var status: CalendarAccess { get }

  /// Fires the OS prompt for `tier`.
  ///
  /// Reports `.success(false)` only for an *answered* refusal. A request that
  /// never reached the user — EventKit handed back an error, or the alert was
  /// torn down by an interruption — reports `.failure`, which is a different
  /// outcome entirely: the OS status stays `notDetermined` and the app must
  /// stay free to ask again. Collapsing the two into one `Bool` would record
  /// an interruption as a permanent refusal.
  func request(_ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void)
}

/// The production `CalendarAuthorization`, backed by EventKit. Every
/// `#available` check in the permission stack lives here.
struct EventKitAuthorization: CalendarAuthorization {
  let eventStore: EKEventStore

  var supportsWriteOnly: Bool {
    if #available(iOS 17.0, *) {
      return true
    }
    return false
  }

  var status: CalendarAccess {
    let status = EKEventStore.authorizationStatus(for: .event)

    if #available(iOS 17.0, *) {
      switch status {
      case .fullAccess:
        return .fullAccess
      case .writeOnly:
        return .writeOnly
      case .denied:
        return .denied
      case .restricted:
        return .restricted
      case .notDetermined:
        return .notDetermined
      @unknown default:
        return .denied
      }
    }

    // iOS 16 and below only has .authorized, which is full access.
    switch status {
    case .authorized:
      return .fullAccess
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .notDetermined:
      return .notDetermined
    // Not `@unknown default`: the iOS 17+ `.writeOnly` case is unreachable
    // here but still counts against exhaustiveness, and a plain `default`
    // maps it to the same `.denied` without the warning.
    default:
      return .denied
    }
  }

  func request(_ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void) {
    let handler: EKEventStoreRequestAccessCompletionHandler = { granted, error in
      if let error = error {
        completion(.failure(error))
      } else {
        completion(.success(granted))
      }
    }

    if #available(iOS 17.0, *) {
      switch tier {
      case .write:
        eventStore.requestWriteOnlyAccessToEvents(completion: handler)
      case .full:
        eventStore.requestFullAccessToEvents(completion: handler)
      }
    } else {
      // iOS 16 and below: only full access exists, and `PermissionService`
      // resolves every ask to `.full` there, so there is nothing to branch on.
      eventStore.requestAccess(to: .event, completion: handler)
    }
  }
}

/// The answer the OS request handler already gave us, if it has answered.
///
/// On iOS 17+ `EKEventStore.authorizationStatus(for:)` can still report
/// `.notDetermined` for a short while afterwards (#134), which made the very
/// next call fail its permission gate until the app was restarted. This is the
/// fallback `RecordingAuthorization` consults while the OS says
/// `.notDetermined`.
///
/// Nothing ever clears it, and nothing needs to: it is only consulted while the
/// OS says `.notDetermined`, so a revocation always wins, and iOS terminates
/// the app when its privacy settings change, so the record cannot outlive the
/// answer it describes.
///
/// Process-wide by design: the answer belongs to the app, not to one
/// `PermissionService`, and a `FlutterEngineGroup` or add-to-app host builds
/// one service per engine. Production uses `shared`; tests inject a fresh
/// instance to stay isolated from each other.
final class AccessRecord {
  static let shared = AccessRecord()

  /// Read from the provider queue (the data endpoints) and from the main
  /// thread (the modal endpoints and the method-channel handlers), and written
  /// from whichever thread EventKit calls the request handler on, so every
  /// access goes through `lock`.
  private let lock = NSLock()
  private var access: CalendarAccess?

  /// Remembers the answer the user just gave, if it is more than we already
  /// knew. The only-ever-upgrade rule is `CalendarAccess.supersedes`, so the
  /// record can never under-report what is held no matter what order answers
  /// arrive in.
  func record(_ answer: CalendarAccess) {
    lock.lock()
    defer { lock.unlock() }
    if answer.supersedes(access) {
      access = answer
    }
  }

  var current: CalendarAccess? {
    lock.lock()
    defer { lock.unlock() }
    return access
  }
}

/// A `CalendarAuthorization` that patches EventKit's stale-status window (#134)
/// where it belongs: behind the seam whose whole job is to make the OS's answer
/// trustworthy, so nothing above it has to know the window exists.
///
/// Reports the live status whenever the OS has one, and falls back to the
/// recorded answer only while the OS still says `.notDetermined` — so a real
/// `.denied` (a Settings revocation, say) is honoured immediately and is never
/// masked by an earlier answer.
final class RecordingAuthorization: CalendarAuthorization {
  private let wrapped: CalendarAuthorization
  private let record: AccessRecord

  init(wrapping wrapped: CalendarAuthorization, record: AccessRecord = .shared) {
    self.wrapped = wrapped
    self.record = record
  }

  var supportsWriteOnly: Bool { wrapped.supportsWriteOnly }

  var status: CalendarAccess {
    let live = wrapped.status
    guard live == .notDetermined else { return live }
    return record.current ?? .notDetermined
  }

  func request(_ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void) {
    wrapped.request(tier) { result in
      // Record before calling back: the caller's very next read may gate on
      // this, and the OS status can still say notDetermined at that point.
      // Only an *answered* request updates the record — a failed one leaves it
      // untouched, so `status` keeps reporting notDetermined and the next ask
      // can still prompt.
      if case .success(let granted) = result {
        self.record.record(granted ? CalendarAccess(granted: tier) : .denied)
      }
      completion(result)
    }
  }
}
