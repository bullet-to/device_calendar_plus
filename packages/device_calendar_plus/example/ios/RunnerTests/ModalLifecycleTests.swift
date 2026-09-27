import EventKitUI
import Flutter
import UIKit
import XCTest

@testable import device_calendar_plus_ios

/// Regressions for #123: paths that used to drop a modal's reply, leaving the
/// Dart `await` hanging. Each one must now reply exactly once.
final class ModalLifecycleTests: XCTestCase {
  private let plugin = DeviceCalendarPlusIosPlugin()

  /// Calendar access refused, whatever the simulator has granted: every
  /// showEventModal lookup fails permissionDenied, deterministically.
  private struct DeniedAuthorization: CalendarAuthorization {
    let supportsWriteOnly = true
    let status = CalendarAccess.denied
    func request(
      _ tier: CalendarPermissionType, completion: @escaping (Result<Bool, Error>) -> Void
    ) {
      completion(.success(false))
    }
  }

  override func setUp() {
    super.setUp()
    plugin.calendarAuthorization = DeniedAuthorization()
  }

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

    // The first call fails its lookup (access is denied) — which frees the
    // slot for the next modal.
    wait(for: [firstReplied], timeout: 5)
    XCTAssertEqual(first, [PlatformExceptionCodes.permissionDenied])

    // So the next call is accepted: it isn't refused on the spot, and it
    // resolves through its own lookup rather than as a busy slot.
    var third: [String] = []
    let thirdReplied = expectation(description: "third call replies")
    plugin.handle(
      FlutterMethodCall(methodName: "showEventModal", arguments: ["eventId": "no-such-event"])
    ) { reply in
      third.append(self.describe(reply))
      thirdReplied.fulfill()
    }
    XCTAssertEqual(third, [])
    wait(for: [thirdReplied], timeout: 5)
    XCTAssertEqual(third, [PlatformExceptionCodes.permissionDenied])
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

  /// The view sheet used to have no presentation delegate, so the swipe-down
  /// above never reached the plugin.
  func testTheViewSheetReportsItsDismissalToThePlugin() {
    let sheet = plugin.eventViewerSheet(for: EKEvent(eventStore: EKEventStore()))

    XCTAssertTrue(sheet.topViewController is EKEventViewController)
    XCTAssertTrue(sheet.presentationController?.delegate === plugin)
  }

  /// The editor handles its own pull-down through its edit delegate, so it
  /// keeps its own presentation delegate.
  func testTheEditorSheetKeepsItsOwnPresentationDelegate() {
    let editor = plugin.eventEditor(for: nil)

    XCTAssertTrue(editor.editViewDelegate === plugin)
    XCTAssertFalse(editor.presentationController?.delegate === plugin)
  }

  // MARK: - presenting

  /// With no window to present from this used to crash (fatalError); it now
  /// fails like Android's no-Activity case and frees the slot.
  func testWithNoRootViewControllerTheModalFailsOperationFailed() throws {
    // Below iOS 17 the blank editor is gated on calendar access first.
    guard #available(iOS 17.0, *) else { throw XCTSkip("Needs the ungated iOS 17 editor") }
    plugin.rootViewController = { nil }

    var replies: [String] = []
    let replied = expectation(description: "create call replies")
    plugin.handle(FlutterMethodCall(methodName: "showCreateEventModal", arguments: nil)) {
      replies.append(self.describe($0))
      replied.fulfill()
    }
    wait(for: [replied], timeout: 5)
    XCTAssertEqual(replies, [PlatformExceptionCodes.operationFailed])

    // The slot is free: the next call resolves through its own lookup, not
    // as a busy slot.
    var next: [String] = []
    let nextReplied = expectation(description: "next call replies")
    plugin.handle(
      FlutterMethodCall(methodName: "showEventModal", arguments: ["eventId": "no-such-event"])
    ) { reply in
      next.append(self.describe(reply))
      nextReplied.fulfill()
    }
    wait(for: [nextReplied], timeout: 5)
    XCTAssertEqual(next, [PlatformExceptionCodes.permissionDenied])
  }

  /// `present` from a controller that's already presenting silently does
  /// nothing, so the modal has to go on top of the stack.
  func testModalsPresentFromTheTopOfThePresentationStack() {
    let root = UIViewController()
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = root
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    XCTAssertTrue(DeviceCalendarPlusIosPlugin.topPresenter(from: root) === root)

    let hostSheet = UIViewController()
    let presented = expectation(description: "host sheet presented")
    root.present(hostSheet, animated: false) { presented.fulfill() }
    wait(for: [presented], timeout: 5)

    XCTAssertTrue(DeviceCalendarPlusIosPlugin.topPresenter(from: root) === hostSheet)
    root.dismiss(animated: false)
  }
}
