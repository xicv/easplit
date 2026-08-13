import Foundation
import XCTest
@testable import eaSplit

@MainActor
final class AppPresentationControllerTests: XCTestCase {
  func testInitialPickerIsPresentedOnlyOnce() throws {
    let suiteName = "AppPresentationControllerTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var presentationCount = 0
    let controller = AppPresentationController(defaults: defaults) {
      presentationCount += 1
    }

    controller.presentInitialPickerIfNeeded()
    controller.presentInitialPickerIfNeeded()

    XCTAssertEqual(presentationCount, 1)
  }

  func testInitialPickerStatePersistsAcrossControllerInstances() throws {
    let suiteName = "AppPresentationControllerTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var presentationCount = 0

    AppPresentationController(defaults: defaults) {
      presentationCount += 1
    }.presentInitialPickerIfNeeded()
    AppPresentationController(defaults: defaults) {
      presentationCount += 1
    }.presentInitialPickerIfNeeded()

    XCTAssertEqual(presentationCount, 1)
  }

  func testReopenAlwaysPresentsPicker() throws {
    let suiteName = "AppPresentationControllerTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var presentationCount = 0
    let controller = AppPresentationController(defaults: defaults) {
      presentationCount += 1
    }

    controller.presentPickerForReopen()
    controller.presentPickerForReopen()

    XCTAssertEqual(presentationCount, 2)
  }

  func testSettingsPresentationActivatesApplicationBeforeOpeningWindow() {
    var events: [String] = []
    let controller = SettingsPresentationController {
      events.append("activated")
    }

    controller.presentSettings {
      events.append("opened")
    }

    XCTAssertEqual(events, ["activated", "opened"])
  }
}
