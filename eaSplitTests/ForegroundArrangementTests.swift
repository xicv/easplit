import Testing
@testable import eaSplit

@MainActor
extension AppModelTests {
  @Test
  func arrangedWindowsAreBroughtForwardByDefault() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }

    #expect(fixture.model.bringArrangedWindowsForward)
  }

  @Test
  func foregroundPreferencePersistsAcrossModelInstances() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }

    fixture.model.bringArrangedWindowsForward = false
    let reloadedModel = AppModel(
      accessibilityClient: fixture.windowController,
      recipeStore: fixture.recipeStore,
      historyStore: fixture.model.historyStore,
      launchAtLogin: fixture.model.launchAtLogin,
      pickerPanelCoordinator: fixture.picker,
      defaults: fixture.defaults
    )

    #expect(!reloadedModel.bringArrangedWindowsForward)
  }

  @Test
  func foregroundPreferenceIsForwardedToTheArrangement() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.bringArrangedWindowsForward = false
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.windowController.broughtArrangedWindowsForward == false)
  }

  @Test
  func foregroundWarningDoesNotUndoASuccessfulArrangement() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(
        arrangedCount: 2,
        failures: [],
        warnings: ["Notes: the window could not be brought forward"]
      )
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.applySelection(closePanel: true)
    await waitWhile { fixture.model.isArranging }

    #expect(!fixture.model.statusIsError)
    #expect(
      fixture.model.statusMessage
        == "Arranged 2 windows; Notes: the window could not be brought forward"
    )
    #expect(fixture.model.canRepeatLastSplit)
    #expect(fixture.picker.dismissCount == 1)
  }
}
