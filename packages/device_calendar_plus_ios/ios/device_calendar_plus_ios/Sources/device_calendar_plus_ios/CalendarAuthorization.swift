import EventKit
import Foundation

/// The OS-level calendar authorization seam. Injected into `PermissionService`
/// so tests can drive the whole grant path — on either side of the iOS 17
/// divide — without a real system prompt. The caller picks the tier; which tier
/// an ask resolves to is policy, and policy lives in `PermissionService`.
protocol CalendarAuthorization {
  /// Whether this OS has the iOS 17+ write-only tier at all.
  var supportsWriteOnly: Bool { get }

  var status: CalendarAccess { get }

  /// Fires the OS prompt for `tier`. `.success(true)` only when the OS confirms
  /// the app now holds `tier`; `.success(false)` says no more than "not that
  /// tier" — iOS 18's "Add Events Only" answers a `.full` ask that way while
  /// granting write-only — so it is never on its own evidence of a refusal. A
  /// request that never reached the user is `.failure`, kept distinct because it
  /// is the one branch nothing downstream can see.
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
  /// `CalendarAccess(ekStatus:supportsWriteOnly:)`.
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
/// fallback `RecordingAuthorization` consults during that window.
///
/// Nothing ever clears it, and nothing needs to: a live status always wins, and
/// iOS terminates the app when its privacy settings change, so the record
/// cannot outlive the grant it describes. The grant belongs to the app rather
/// than to one `PermissionService`, hence `shared` in production.
final class AccessRecord {
  static let shared = AccessRecord()

  /// Read and written from whichever threads the endpoints and EventKit's
  /// request handler happen to run on, so every access goes through `lock`.
  private let lock = NSLock()
  private var granted: CalendarAccess?

  /// Keeps the highest tier seen, so the record only ever climbs the lattice
  /// whatever order concurrent answers arrive in. Taking the tier rather than a
  /// `CalendarAccess` is what makes "a refusal is never remembered" a fact about
  /// the signature.
  func record(granted tier: CalendarPermissionType) {
    let answer = CalendarAccess(granted: tier)
    lock.lock()
    defer { lock.unlock() }
    if answer.rank > (granted?.rank ?? 0) {
      granted = answer
    }
  }

  var current: CalendarAccess? {
    lock.lock()
    defer { lock.unlock() }
    return granted
  }
}

/// Patches EventKit's stale-status window (#134) behind the seam, so nothing
/// above has to know the window exists. Reports the live status whenever the OS
/// has one and falls back to the recorded grant only while it still says
/// `.notDetermined` — so a Settings revocation is honoured immediately and is
/// never masked by an earlier grant.
final class RecordingAuthorization: CalendarAuthorization {
  private let wrapped: CalendarAuthorization
  private let record: AccessRecord

  init(wrapping wrapped: CalendarAuthorization, record: AccessRecord) {
    self.wrapped = wrapped
    self.record = record
  }

  var supportsWriteOnly: Bool { wrapped.supportsWriteOnly }

  var status: CalendarAccess {
    let live = wrapped.status
    guard live == .notDetermined else { return live }
    return record.current ?? .notDetermined
  }

  /// Records grants and nothing else, because `granted == false` means "not
  /// that tier" rather than a refusal — an iOS 18 "Add Events Only" answer to a
  /// full ask reports `false` while granting write-only. Remembering that as
  /// `.denied` would fail every write gate until the process restarted, since
  /// nothing clears the record and `requestPermissions` will not re-prompt on a
  /// terminal answer; forgetting a real refusal costs one redundant OS call.
  ///
  /// The residual — that same answer reports `.notDetermined` until the live
  /// status catches up, so a `createEvent` fired immediately after the prompt
  /// can still fail its gate — is tracked on #137.
  func request(_ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void) {
    wrapped.request(tier) { result in
      // Record before calling back: the caller's very next read may gate on
      // this, and the OS status can still say notDetermined at that point.
      if case .success(true) = result {
        self.record.record(granted: tier)
      }
      completion(result)
    }
  }
}
