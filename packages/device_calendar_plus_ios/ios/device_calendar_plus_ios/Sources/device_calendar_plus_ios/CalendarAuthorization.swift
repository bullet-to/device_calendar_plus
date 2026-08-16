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
  /// Reports `.success(true)` only when the OS confirms the app now holds
  /// `tier`. `.success(false)` says no more than "not that tier" — on iOS 18
  /// the full-access alert has a middle "Add Events Only" choice, which answers
  /// a `.full` ask with `false` while granting write-only — so it is never on
  /// its own evidence of a refusal.
  ///
  /// A request that never reached the user — EventKit handed back an error, or
  /// the alert was torn down by an interruption — reports `.failure`, which is
  /// a different outcome again and worth surfacing rather than folding into a
  /// `Bool`: it is the one branch nothing downstream can see, so
  /// `PermissionService` logs it.
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

  /// Only the store lookup lives here; the version-dependent mapping is
  /// `CalendarAccess(ekStatus:supportsWriteOnly:)`, which is pure and pinned by
  /// `CalendarAccessTests`.
  var status: CalendarAccess {
    CalendarAccess(
      ekStatus: EKEventStore.authorizationStatus(for: .event),
      supportsWriteOnly: supportsWriteOnly)
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

/// The grant the OS request handler already confirmed, if there is one.
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
/// grant it describes.
///
/// Process-wide by design: the grant belongs to the app, not to one
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
  private var granted: CalendarAccess?

  /// Remembers a confirmed grant, keeping the highest tier seen.
  ///
  /// Only grants are ever recorded (see `RecordingAuthorization.request`), so
  /// the values here are `.writeOnly` or `.fullAccess` and the only-ever-upgrade
  /// rule is one line: once full access is held there is nothing left to upgrade
  /// to, and any other answer is at most what we already know. That keeps the
  /// record monotonic whatever order answers arrive in.
  func record(_ answer: CalendarAccess) {
    lock.lock()
    defer { lock.unlock() }
    guard granted?.satisfies(.full) != true else { return }
    granted = answer
  }

  var current: CalendarAccess? {
    lock.lock()
    defer { lock.unlock() }
    return granted
  }
}

/// A `CalendarAuthorization` that patches EventKit's stale-status window (#134)
/// where it belongs: behind the seam whose whole job is to make the OS's answer
/// trustworthy, so nothing above it has to know the window exists.
///
/// Reports the live status whenever the OS has one, and falls back to the
/// recorded grant only while the OS still says `.notDetermined` — so a real
/// `.denied` (a Settings revocation, say) is honoured immediately and is never
/// masked by an earlier grant.
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

  /// Records grants and nothing else.
  ///
  /// `granted == false` is not a refusal of *everything*: it means the app did
  /// not get the tier it asked for. On iOS 18 the full-access alert offers a
  /// middle "Add Events Only" choice, so a user who picks it produces
  /// `granted == false` while the app actually holds write-only. Recording that
  /// as `.denied` would fail every write gate for the rest of the process —
  /// nothing can clear the record, and `requestPermissions` would refuse to
  /// re-prompt on a terminal answer.
  ///
  /// The failure modes are asymmetric. Forgetting a refusal costs at most one
  /// redundant OS call — EventKit invokes the handler immediately, with no UI,
  /// for a permission the user has already answered — and the live status takes
  /// over the moment it catches up. Remembering a refusal that never happened
  /// is unrecoverable short of an app restart, which is the #134 class of bug
  /// this seam exists to end.
  func request(_ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void) {
    wrapped.request(tier) { result in
      // Record before calling back: the caller's very next read may gate on
      // this, and the OS status can still say notDetermined at that point.
      if case .success(true) = result {
        self.record.record(CalendarAccess(granted: tier))
      }
      completion(result)
    }
  }
}
