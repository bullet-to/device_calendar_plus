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
/// Nothing ever clears it, and nothing needs to: a terminal live status wins
/// outright, so a Settings revocation is never masked, and iOS terminates the
/// app when its privacy settings change, so the record cannot outlive the grant
/// it describes. The grant belongs to the app rather than to one
/// `PermissionService`, hence `shared` in production.
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

/// Patches EventKit's stale-status window behind the seam, in both
/// directions, so nothing above has to know the window exists:
///
/// - **After a grant** (#134) it *records* the tier the OS confirmed, and
///   reports that record whenever it outranks the lagging live status.
/// - **After an ungranted answer** (#137) it *waits* for the status to settle;
///   see `request(_:completion:)`.
///
/// Together these are the guarantee `PermissionService` leans on: once
/// `request(_:completion:)` calls back, `status` reports the tier the OS
/// settled on — or `.notDetermined` if the request errored, or the status
/// never left it within the bounded wait (about a second). The raw `EventKitAuthorization` makes no such
/// promise; that lag is the bug.
///
/// `.denied` and `.restricted` are terminal and reported as-is, so a Settings
/// revocation is honoured immediately and is never masked by an earlier
/// grant. Below that, the recorded grant wins whenever it outranks the live
/// status — the OS confirmed that tier, so a lower live status is stale rather
/// than authoritative.
final class RecordingAuthorization: CalendarAuthorization {
  /// Runs its argument a moment later. Injected so tests drive the wait for a
  /// lagging status without a real clock.
  typealias Deferral = (@escaping () -> Void) -> Void

  /// The bounded wait for an ungranted answer's status to leave
  /// `.notDetermined`: `settleChecks` re-reads, `settleInterval` apart, is
  /// about a second in production.
  private static let settleInterval: TimeInterval = 0.05
  private static let settleChecks = 20

  /// The production wait between re-reads of a lagging status.
  static let settleDelay: Deferral = { work in
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + RecordingAuthorization.settleInterval, execute: work)
  }

  private let wrapped: CalendarAuthorization
  private let record: AccessRecord
  private let deferral: Deferral

  init(
    wrapping wrapped: CalendarAuthorization,
    record: AccessRecord,
    deferral: @escaping Deferral = RecordingAuthorization.settleDelay
  ) {
    self.wrapped = wrapped
    self.record = record
    self.deferral = deferral
  }

  var supportsWriteOnly: Bool { wrapped.supportsWriteOnly }

  /// A terminal answer is the OS's alone. Otherwise the higher of the live
  /// status and the recorded grant wins: a `.full` ask only answers `granted ==
  /// true` for real full access (iOS 18's "Add Events Only" answers `false`),
  /// so a live status *below* what the OS confirmed — `.notDetermined` on a
  /// fresh grant, `.writeOnly` on an in-app upgrade — has yet to catch up.
  var status: CalendarAccess {
    let live = wrapped.status
    guard !live.isTerminal else { return live }
    guard let recorded = record.current, recorded.rank > live.rank else { return live }
    return recorded
  }

  /// Records grants and nothing else, because `granted == false` means "not
  /// that tier" rather than a refusal — an iOS 18 "Add Events Only" answer to a
  /// full ask reports `false` while granting write-only. Remembering that as
  /// `.denied` would fail every write gate until the process restarted, since
  /// nothing clears the record and `requestPermissions` will not re-prompt on a
  /// terminal answer; forgetting a real refusal costs one redundant OS call.
  ///
  /// An ungranted answer is not guessed at either: it waits instead, briefly,
  /// for the live status to leave `.notDetermined` (#137). The same stale
  /// window that hides a grant hides an "Add Events Only" answer too, and the
  /// caller's very next read — `requestPermissions`' report, then the gate on a
  /// `createEvent` fired straight after it — must see the tier the OS settles
  /// on, not the lag. A refusal settles on `.denied` just the same, and a
  /// status that never moves costs a bounded wait before reporting
  /// `.notDetermined` as before.
  func request(_ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void) {
    wrapped.request(tier) { result in
      switch result {
      case .success(true):
        // Record before calling back: the caller's very next read may gate on
        // this, and the OS status can still say notDetermined at that point.
        self.record.record(granted: tier)
        completion(result)
      case .success(false):
        self.awaitSettledStatus(checksLeft: Self.settleChecks) { completion(result) }
      case .failure:
        completion(result)
      }
    }
  }

  /// Calls `done` once `status` has left `.notDetermined`, or once the checks
  /// run out. Reads the patched `status`, so a recorded grant that already
  /// outranks the lag — an upgrade answered "not that tier" — needs no wait.
  private func awaitSettledStatus(checksLeft: Int, then done: @escaping () -> Void) {
    guard status == .notDetermined else {
      done()
      return
    }
    guard checksLeft > 0 else {
      // The bound is a guess at EventKit's lag; if a real device outlasts it,
      // #137 is back, so leave a trace in the device log.
      NSLog(
        "device_calendar_plus: authorization status still notDetermined after an ungranted answer; reporting it"
      )
      done()
      return
    }
    deferral { self.awaitSettledStatus(checksLeft: checksLeft - 1, then: done) }
  }
}
