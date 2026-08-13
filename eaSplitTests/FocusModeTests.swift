import AppKit
import Testing
@testable import eaSplit

@MainActor
extension AppModelTests {
  @Test
  func successfulFocusSplitHidesOnlyUnselectedApplications() async throws {
    let fixture = try makeFixture(
      windows: Self.focusWindows(),
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.hideOtherApplicationsAfterSplit = true
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.applicationVisibilityController.hiddenApplicationIDs == [300])
  }

  @Test
  func partialFocusSplitDoesNotHideOtherApplications() async throws {
    let fixture = try makeFixture(
      windows: Self.focusWindows(),
      arrangementResult: ArrangementResult(
        arrangedCount: 1,
        failures: ["Notes: the application did not respond"]
      )
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.hideOtherApplicationsAfterSplit = true
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.applicationVisibilityController.completeCallCount == 0)
    #expect(fixture.applicationVisibilityController.cancelCallCount == 1)
    #expect(fixture.applicationVisibilityController.hiddenApplicationIDs.isEmpty)
  }

  @Test
  func undoRestoresAppsHiddenByTheFocusSplit() async throws {
    let fixture = try makeFixture(
      windows: Self.focusWindows(),
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: []),
      undoResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.hideOtherApplicationsAfterSplit = true
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }
    #expect(fixture.model.canUndo)

    fixture.model.undo()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.applicationVisibilityController.undoCallCount == 1)
    #expect(fixture.applicationVisibilityController.hiddenApplicationIDs.isEmpty)
    #expect(fixture.model.statusMessage == "Restored 2 windows")
  }

  @Test
  func focusPreferenceDefaultsOffAndPersists() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }

    #expect(!fixture.model.hideOtherApplicationsAfterSplit)
    fixture.model.hideOtherApplicationsAfterSplit = true

    let reloadedModel = AppModel(
      accessibilityClient: fixture.windowController,
      applicationVisibilityController: fixture.applicationVisibilityController,
      recipeStore: fixture.recipeStore,
      historyStore: fixture.model.historyStore,
      launchAtLogin: fixture.model.launchAtLogin,
      pickerPanelCoordinator: fixture.picker,
      defaults: fixture.defaults
    )

    #expect(reloadedModel.hideOtherApplicationsAfterSplit)
  }

  private static func focusWindows() -> [WindowDescriptor] {
    [
      makeWindow(processIdentifier: 100, applicationName: "Safari", isFocused: true),
      makeWindow(processIdentifier: 200, applicationName: "Notes"),
      makeWindow(processIdentifier: 300, applicationName: "Calendar"),
    ]
  }

  private static func makeWindow(
    processIdentifier: pid_t,
    applicationName: String,
    isFocused: Bool = false
  ) -> WindowDescriptor {
    WindowDescriptor(
      id: UUID(),
      processIdentifier: processIdentifier,
      applicationName: applicationName,
      bundleIdentifier: "com.example.\(applicationName.lowercased())",
      title: applicationName,
      icon: NSImage(),
      frame: CGRect(x: 0, y: 0, width: 500, height: 800),
      isFocused: isFocused
    )
  }
}
