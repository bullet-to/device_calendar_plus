import Flutter

/// The reply for the one native modal that's showing (#123).
///
/// The modal endpoints complete when the modal is dismissed, so their channel
/// reply is held here until `complete()`. Every path out of the slot replies
/// exactly once — a reply that's dropped leaves the Dart `await` hanging
/// forever.
///
/// One modal at a time, across both kinds: a view controller presents only one
/// modal, so a second call while one is showing fails with `OPERATION_FAILED`
/// rather than overwriting (and so orphaning) the first reply. The slot is
/// claimed as the call arrives, before the event lookup, so two calls in the
/// same run-loop turn can't both get through. Main thread only.
final class PendingModal {
  private var result: FlutterResult?

  /// Claims the slot for `result`. When a modal is already showing, replies
  /// `OPERATION_FAILED` to `result` and returns false.
  func begin(_ result: @escaping FlutterResult) -> Bool {
    if self.result != nil {
      result(FlutterError(
        code: PlatformExceptionCodes.operationFailed,
        message: "A calendar modal is already showing",
        details: nil))
      return false
    }
    self.result = result
    return true
  }

  /// The modal closed: reply and free the slot.
  func complete() {
    take()?(nil)
  }

  /// The modal couldn't be shown: reply with the error and free the slot.
  func fail(code: String, message: String?) {
    take()?(FlutterError(code: code, message: message, details: nil))
  }

  private func take() -> FlutterResult? {
    let pending = result
    result = nil
    return pending
  }
}
