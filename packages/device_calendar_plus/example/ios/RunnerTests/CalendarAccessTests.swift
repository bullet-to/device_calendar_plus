import EventKit
import XCTest

@testable import device_calendar_plus_ios

/// The two pure pieces of `CalendarAccess`: the EventKit status mapping, which
/// differs on either side of the iOS 17 divide, and the wire format Dart parses.
/// Neither needs an event store, so both are pinned here rather than reached
/// through `PermissionService`.
final class CalendarAccessTests: XCTestCase {
  private typealias Access = CalendarAccess

  // MARK: - init(ekStatus:supportsWriteOnly:)

  /// iOS 17+ has the tiers, and each one maps to itself.
  func testEkStatusMapsEachTierWhereTheOsHasThem() throws {
    guard #available(iOS 17.0, *) else {
      throw XCTSkip("the write-only tier does not exist before iOS 17")
    }

    for (ekStatus, expected) in [
      (EKAuthorizationStatus.fullAccess, Access.fullAccess),
      (.writeOnly, .writeOnly),
      (.denied, .denied),
      (.restricted, .restricted),
      (.notDetermined, .notDetermined),
    ] {
      XCTAssertEqual(
        Access(ekStatus: ekStatus, supportsWriteOnly: true), expected, "\(ekStatus.rawValue)")
    }
  }

  /// iOS 13-16 only has `.authorized`, and it means full access. The mapping
  /// branches on the injected capability rather than `#available`, so this runs
  /// on a modern simulator — an OS nobody keeps a device for otherwise.
  ///
  /// A status the OS has no business reporting there (`.writeOnly`) must
  /// degrade to `.denied` rather than be read as a grant: that branch is the
  /// plain `default`, so nothing else would catch a mistake in it. An
  /// altogether unknown raw value takes the same branch, but `EventKit`'s
  /// imported enum refuses to build one, so it can't be driven from a test.
  func testEkStatusTreatsOnlyAuthorizedAsAccessWhereTheOsHasNoTiers() throws {
    var expectations: [(EKAuthorizationStatus, Access)] = [
      (.authorized, .fullAccess),
      (.denied, .denied),
      (.restricted, .restricted),
      (.notDetermined, .notDetermined),
    ]
    if #available(iOS 17.0, *) {
      expectations.append((.writeOnly, .denied))
    }

    for (ekStatus, expected) in expectations {
      XCTAssertEqual(
        Access(ekStatus: ekStatus, supportsWriteOnly: false), expected, "\(ekStatus.rawValue)")
    }
  }

  // MARK: - wireValue

  /// The wire values cross the method channel and Dart's
  /// `CalendarPermissionStatus` parses them by name, degrading anything it does
  /// not recognise to `denied` without an exception — so a rename would surface
  /// as a mystery permission failure in the field rather than a red test.
  /// Pinned to literals here; every other assertion stays symbolic.
  func testWireValuesAreTheStringsDartParses() {
    XCTAssertEqual(
      [Access.fullAccess, .writeOnly, .denied, .restricted, .notDetermined].map(\.wireValue),
      ["granted", "writeOnly", "denied", "restricted", "notDetermined"])
  }
}
