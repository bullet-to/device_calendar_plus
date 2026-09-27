import Flutter
import UIKit
import XCTest

@testable import device_calendar_plus_ios

/// Regressions for #123: paths that used to drop a modal's reply, leaving the
/// Dart `await` hanging. Each one must now reply exactly once.
final class ModalLifecycleTests: XCTestCase {
  private let plugin = DeviceCalendarPlusIosPlugin()

  /// What a channel reply carried: the error code, or "success".
  private func describe(_ reply: Any?) -> String {
    (reply as? FlutterError)?.code ?? "success"
  }

  // MARK: - one modal at a time

  /// The second call used to overwrite the first's reply, and its `present`
  /// silently failed on the already-presenting root — both awaits hung.
  func testASecondModalCallWhileOneIsPendingFailsAtOnce() {
    var first: [String] = []
    var second: [String] = []
    let firstReplied = expectation(description: "first call replies")

    plugin.handle(
      FlutterMethodCall(methodName: "showEventModal", arguments: ["eventId": "no-such-event"])
    ) { reply in
      first.append(self.describe(reply))
      firstReplied.fulfill()
    }
    plugin.handle(FlutterMethodCall(methodName: "showCreateEventModal", arguments: nil)) {
      second.append(self.describe($0))
    }

    XCTAssertEqual(second, [PlatformExceptionCodes.operationFailed])

    // The first call fails its lookup (no access, or no such event) — which
    // frees the slot for the next modal.
    wait(for: [firstReplied], timeout: 5)
    XCTAssertEqual(first.count, 1)
    XCTAssertNotEqual(first.first, "success")
    XCTAssertTrue(plugin.pendingModal.begin { _ in })
  }

  // MARK: - swipe-down

  /// Swiping the view modal down skips `eventViewController(_:didCompleteWith:)`,
  /// so the dismissal itself has to resolve the reply.
  func testSwipingTheModalDownResolvesThePendingReply() {
    var replies: [String] = []
    XCTAssertTrue(plugin.pendingModal.begin { replies.append(self.describe($0)) })

    let sheet = UIPresentationController(presentedViewController: UIViewController(), presenting: nil)
    plugin.presentationControllerDidDismiss(sheet)
    plugin.presentationControllerDidDismiss(sheet)

    XCTAssertEqual(replies, ["success"])
  }
}
