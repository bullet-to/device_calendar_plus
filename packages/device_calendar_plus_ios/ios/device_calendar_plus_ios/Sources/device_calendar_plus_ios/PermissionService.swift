import Foundation

/// Reads an Info.plist usage description by key. Injected so the
/// configuration-error paths are testable without a bundle: like the OS
/// authorization status, "what did this app declare" is an OS-shaped fact and
/// belongs behind a seam.
typealias UsageDescriptionLookup = (String) -> String?

/// The permission policy: which tier an ask resolves to, which grants satisfy
/// which gates, and what Dart is told. It holds no version knowledge of its own
/// — the `CalendarAuthorization` seam answers that — and no knowledge of
/// EventKit's stale-status window, which `RecordingAuthorization` hides behind
/// the same seam.
class PermissionService {
  /// The production lookup: the host app's own Info.plist, which is what the OS
  /// itself reads when it decides whether a prompt is allowed.
  static let mainBundleUsageDescriptions: UsageDescriptionLookup = {
    Bundle.main.object(forInfoDictionaryKey: $0) as? String
  }

  private let authorization: CalendarAuthorization
  private let usageDescriptions: UsageDescriptionLookup

  init(
    authorization: CalendarAuthorization,
    usageDescriptions: @escaping UsageDescriptionLookup =
      PermissionService.mainBundleUsageDescriptions
  ) {
    self.authorization = authorization
    self.usageDescriptions = usageDescriptions
  }

  /// Checks if calendar permissions are granted for the specified access level.
  ///
  /// - Parameter type: The type of access required (.write or .full)
  /// - Returns: true if the required permission level is granted
  func hasPermission(for type: CalendarPermissionType = .full) -> Bool {
    authorization.status.satisfies(type)
  }

  // Info.plist usage-description keys. The declaration checks and the error
  // messages must name the same keys, so both go through these constants and
  // the shared descriptionExample map.
  private static let legacyUsageKey = "NSCalendarsUsageDescription"
  private static let fullAccessUsageKey = "NSCalendarsFullAccessUsageDescription"
  private static let writeOnlyUsageKey = "NSCalendarsWriteOnlyAccessUsageDescription"

  private static let descriptionExamples: [String: String] = [
    legacyUsageKey: "Access your calendar to view and manage events.",
    fullAccessUsageKey: "Full access to view and edit your calendar events.",
    writeOnlyUsageKey: "Add events without reading existing events.",
  ]

  private func isDescriptionDeclared(_ key: String) -> Bool {
    !(usageDescriptions(key)?.isEmpty ?? true)
  }

  private func missingDescriptionError(_ title: String, keys: [String]) -> PermissionError {
    var errorMessage = "\(title) not declared in Info.plist.\n\n"
    errorMessage += "Add the following to ios/Runner/Info.plist:"
    for key in keys {
      errorMessage += "\n<key>\(key)</key>"
      errorMessage += "\n<string>\(PermissionService.descriptionExamples[key] ?? "")</string>"
    }

    return PermissionError(code: PlatformExceptionCodes.permissionsNotDeclared, message: errorMessage)
  }

  private func missingWriteOnlyDescriptionError() -> PermissionError {
    missingDescriptionError(
      "Write-only calendar usage description",
      keys: [PermissionService.writeOnlyUsageKey])
  }

  private func missingFullAccessDescriptionError() -> PermissionError {
    missingDescriptionError(
      "Full-access calendar usage description",
      keys: [PermissionService.fullAccessUsageKey])
  }

  /// The no-keys-at-all error. Lists every key so following the advice once
  /// satisfies both the status guard and any later request on any OS version —
  /// naming only the legacy key would fix `hasPermissions` and then fail again
  /// on an iOS 17+ request, which demands the tier-specific keys.
  private func missingUsageDescriptionError() -> PermissionError {
    missingDescriptionError(
      "Calendar usage description",
      keys: [
        PermissionService.fullAccessUsageKey,
        PermissionService.writeOnlyUsageKey,
        PermissionService.legacyUsageKey,
      ])
  }

  /// Verifies the Info.plist declares the usage description the request needs.
  ///
  /// On iOS 17+ each request variant **requires** its own key: full access
  /// (`requestFullAccessToEvents`) needs `NSCalendarsFullAccessUsageDescription`
  /// and write-only needs `NSCalendarsWriteOnlyAccessUsageDescription` — the
  /// legacy `NSCalendarsUsageDescription` no longer satisfies either, and
  /// without the matching key the OS raises an exception, so we surface a
  /// clear error instead of crashing. iOS 16 and below uses only the legacy key.
  ///
  /// Takes the resolved tier rather than the caller's raw `writeOnly` flag, so
  /// the "which tier is this ask" question is answered exactly once, in
  /// `requestPermissions`.
  private func checkUsageDescriptionDeclared(for tier: CalendarPermissionType) -> PermissionError? {
    guard authorization.supportsWriteOnly else {
      return isDescriptionDeclared(PermissionService.legacyUsageKey)
        ? nil : missingDescriptionError(
          "Calendar usage description", keys: [PermissionService.legacyUsageKey])
    }

    switch tier {
    case .write:
      return isDescriptionDeclared(PermissionService.writeOnlyUsageKey)
        ? nil : missingWriteOnlyDescriptionError()
    case .full:
      return isDescriptionDeclared(PermissionService.fullAccessUsageKey)
        ? nil : missingFullAccessDescriptionError()
    }
  }

  func hasPermissions() -> Result<CalendarAccess, PermissionError> {
    // A status check triggers no prompt, so any declared calendar usage
    // description — legacy, full-access, or write-only — satisfies the
    // configuration guard. An add-only app that declares only the write-only
    // key can still check status.
    guard isDescriptionDeclared(PermissionService.legacyUsageKey)
      || isDescriptionDeclared(PermissionService.fullAccessUsageKey)
      || isDescriptionDeclared(PermissionService.writeOnlyUsageKey) else {
      return .failure(missingUsageDescriptionError())
    }

    return .success(authorization.status)
  }

  /// Requests calendar access from the user.
  /// - Parameter writeOnly: when `true`, asks for add-only (write-only) access
  ///   where the OS supports it (iOS 17+). On iOS 16 and below write-only does
  ///   not exist, so the request falls back to full access regardless.
  func requestPermissions(
    writeOnly: Bool,
    completion: @escaping (Result<CalendarAccess, PermissionError>) -> Void
  ) {
    // The tier this ask resolves to. Write-only exists only where the OS
    // supports it, so elsewhere every ask resolves to full access — the one
    // place the version difference is decided.
    let tier: CalendarPermissionType =
      writeOnly && authorization.supportsWriteOnly ? .write : .full

    let access = authorization.status

    // Nothing to prompt for if we already hold a tier that satisfies the ask
    // (a full request while only write-only is held does *not*, so it falls
    // through), or if the answer can only be changed in Settings.
    if access.satisfies(tier) || access.isTerminal {
      completion(.success(access))
      return
    }

    // The usage-description key is only needed once we actually fire an OS
    // request, so the check sits after the early returns — an app that ships
    // without the (iOS 17+) tier key must still get its already-granted or
    // terminal status back rather than a configuration error.
    if let error = checkUsageDescriptionDeclared(for: tier) {
      completion(.failure(error))
      return
    }

    // Otherwise attempt the request. This prompts on a fresh notDetermined, and
    // also on a full request while only write-only is held — iOS re-presents the
    // dialog asking for full access and upgrades the app in-app if the user
    // agrees.
    authorization.request(tier) { _ in
      // Re-read rather than translate the answer: the seam has already folded
      // an answered grant or refusal into its status, and a request that never
      // got an answer left it alone, so this reports the truth on every branch
      // — including "still notDetermined, ask again" after a failed request.
      completion(.success(self.authorization.status))
    }
  }
}

struct PermissionError: Error {
  let code: String
  let message: String
}
