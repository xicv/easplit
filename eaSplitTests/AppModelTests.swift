import AppKit
import Foundation
import ServiceManagement
import Testing
@testable import eaSplit

@Suite(.serialized)
@MainActor
struct AppModelTests {
  @Test
  func partialArrangementStaysOpenAndCannotBeRepeated() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(
        arrangedCount: 1,
        failures: ["Notes: the application did not respond"]
      )
    )
    defer { fixture.cleanUp() }
    let windows = fixture.windowController.windows

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.selectedLayout = .twoColumns
    fixture.model.selectedWindowIDs = windows.map(\.id)

    fixture.model.applySelection(closePanel: true)
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.statusIsError)
    #expect(fixture.model.statusMessage == "Arranged 1; 1 could not be moved")
    #expect(!fixture.model.canRepeatLastSplit)
    #expect(fixture.picker.dismissCount == 0)
  }

  @Test
  func successfulArrangementClosesAndCanBeRepeated() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }
    let windows = fixture.windowController.windows

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.selectedLayout = .twoColumns
    fixture.model.selectedWindowIDs = windows.map(\.id)
    fixture.model.edgeToEdgeWindows = true

    fixture.model.applySelection(closePanel: true)
    await waitWhile { fixture.model.isArranging }

    #expect(!fixture.model.statusIsError)
    #expect(fixture.model.statusMessage == "Arranged 2 windows")
    #expect(fixture.model.canRepeatLastSplit)
    #expect(fixture.picker.dismissCount == 1)
    #expect(fixture.windowController.arrangedGap == 0)
  }

  @Test
  func twoSuccessfulArrangementsCreateAFrequentSuggestion() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }
    #expect(fixture.model.suggestion == nil)

    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.suggestion?.reason == .frequentlyUsed(count: 2))
    #expect(fixture.model.suggestion?.windowIDs == fixture.windowController.windows.map(\.id))
  }

  @Test
  func savedSuggestionAppliesItsCompleteArrangementInOneAction() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }
    fixture.recipeStore.add(
      SplitRecipe(
        name: "Writing",
        layout: .twoRows,
        ratio: .leading,
        slots: [
          .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
          .init(bundleIdentifier: "com.apple.Notes", applicationName: "Notes"),
        ],
        spacing: .init(edgeToEdge: false, gap: 14)
      )
    )

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    #expect(fixture.model.suggestion?.reason == .saved(name: "Writing"))

    fixture.model.applySuggestion(closePanel: true)
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.selectedLayout == .twoRows)
    #expect(fixture.model.selectedRatio == .leading)
    #expect(fixture.model.gap == 14)
    #expect(fixture.windowController.arrangedWindowIDs == fixture.windowController.windows.map(\.id))
    #expect(fixture.windowController.arrangedGap == 14)
    #expect(fixture.picker.dismissCount == 1)
  }

  @Test
  func failedArrangementIsNeverLearned() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(
        arrangedCount: 1,
        failures: ["Notes: the application did not respond"]
      )
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.suggestion == nil)
  }

  @Test
  func disablingSuggestionsStopsLearningAndClearsPresentation() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.suggestionsEnabled = false
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }
    fixture.model.applySelection()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.suggestion == nil)
  }

  @Test
  func successfulUndoReportsRestoredWindows() async throws {
    let fixture = try makeFixture(
      undoResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }

    fixture.model.undo()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.statusMessage == "Restored 2 windows")
    #expect(!fixture.model.statusIsError)
  }

  @Test
  func partialUndoReportsWindowsThatCouldNotBeRestored() async throws {
    let fixture = try makeFixture(
      undoResult: ArrangementResult(
        arrangedCount: 1,
        failures: ["Notes: the application did not respond"]
      )
    )
    defer { fixture.cleanUp() }

    fixture.model.undo()
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.model.statusMessage == "Restored 1; 1 could not be restored")
    #expect(fixture.model.statusIsError)
  }

  @Test
  func initializationDefersWindowDiscoveryUntilRefresh() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }

    for _ in 0..<10 { await Task.yield() }
    #expect(fixture.windowController.discoverCallCount == 0)

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    #expect(fixture.windowController.discoverCallCount == 1)
  }

  @Test
  func windowRefreshDoesNotQueryLaunchAtLoginStatus() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }

    #expect(fixture.launchAtLoginService.statusRequestCount == 0)
  }

  @Test
  func settingsRefreshLoadsLaunchAtLoginStatus() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }

    fixture.model.refreshSettings()

    #expect(fixture.model.launchAtLogin.hasLoadedStatus)
    #expect(fixture.launchAtLoginService.statusRequestCount == 1)
  }

  @Test
  func refreshRequestsNeverOverlapAndRunTheLatestRequest() async throws {
    let fixture = try makeFixture(blockFirstDiscovery: true)
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitUntil { fixture.windowController.discoverCallCount == 1 }

    fixture.model.refreshWindows()
    for _ in 0..<10 { await Task.yield() }

    #expect(fixture.windowController.discoverCallCount == 1)
    #expect(fixture.windowController.maximumConcurrentDiscoveries == 1)

    fixture.windowController.releaseFirstDiscovery()
    await waitWhile { fixture.model.isRefreshing }

    #expect(fixture.windowController.discoverCallCount == 2)
    #expect(fixture.windowController.maximumConcurrentDiscoveries == 1)
  }

  @Test
  func quickSplitWaitsForTheCoalescedRefresh() async throws {
    let fixture = try makeFixture(
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: []),
      blockFirstDiscovery: true
    )
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitUntil { fixture.windowController.discoverCallCount == 1 }
    fixture.model.quickSplit()

    fixture.windowController.releaseFirstDiscovery()
    await waitUntil { fixture.windowController.arrangeCallCount == 1 }

    #expect(fixture.windowController.discoverCallCount == 2)
    #expect(fixture.windowController.maximumConcurrentDiscoveries == 1)
    #expect(fixture.windowController.arrangedWindowIDs == fixture.windowController.windows.map(\.id))
  }

  @Test
  func quickSplitWithTooFewWindowsExplainsAndOpensPicker() async throws {
    let fixture = try makeFixture(windows: [Self.makeWindows()[0]])
    defer { fixture.cleanUp() }

    fixture.model.quickSplit()
    await waitUntil { fixture.model.statusMessage != nil }

    #expect(fixture.model.statusMessage == "Open two resizable application windows first.")
    #expect(fixture.model.statusIsError)
    #expect(fixture.picker.showCount == 1)
    #expect(fixture.windowController.arrangeCallCount == 0)
  }

  @Test
  func recipeUsesDistinctWindowsFromTheSameApplication() async throws {
    let windows = Self.makeSameApplicationWindows()
    let fixture = try makeFixture(
      windows: windows,
      arrangementResult: ArrangementResult(arrangedCount: 2, failures: [])
    )
    defer { fixture.cleanUp() }
    let recipe = SplitRecipe(
      name: "Research",
      layout: .twoColumns,
      ratio: .leading,
      slots: windows.map {
        SplitRecipe.Slot(
          bundleIdentifier: $0.bundleIdentifier ?? "",
          applicationName: $0.applicationName
        )
      }
    )

    fixture.model.apply(recipe, closePanel: true)
    await waitUntil { fixture.windowController.arrangeCallCount == 1 }
    await waitWhile { fixture.model.isArranging }

    #expect(fixture.windowController.arrangedWindowIDs == windows.map(\.id))
    #expect(fixture.model.selectedRatio == .leading)
    #expect(fixture.picker.dismissCount == 1)
  }

  @Test
  func windowSelectionKeepsSlotOrderAndCapacity() async throws {
    let windows = Self.makeWindows()
    let thirdWindow = WindowDescriptor(
      id: UUID(),
      processIdentifier: 300,
      applicationName: "Calendar",
      bundleIdentifier: "com.apple.Calendar",
      title: "Calendar",
      icon: NSImage(),
      frame: CGRect(x: 0, y: 0, width: 500, height: 800),
      isFocused: false
    )
    let fixture = try makeFixture(windows: windows + [thirdWindow])
    defer { fixture.cleanUp() }
    fixture.model.selectedWindowIDs = []

    fixture.model.toggleWindow(windows[0])
    fixture.model.toggleWindow(windows[1])
    fixture.model.toggleWindow(thirdWindow)

    #expect(fixture.model.selectedWindowIDs == [windows[0].id, thirdWindow.id])
    #expect(fixture.model.selectionNumber(for: windows[0]) == 1)
    #expect(fixture.model.selectionNumber(for: thirdWindow) == 2)

    fixture.model.toggleWindow(windows[0])
    #expect(fixture.model.selectedWindowIDs == [thirdWindow.id])
  }

  @Test
  func refreshDoesNotReplaceASelectedWindowThatDisappeared() async throws {
    let initialWindows = Self.makeWindows() + [
      Self.makeWindow(processIdentifier: 300, applicationName: "Calendar"),
      Self.makeWindow(processIdentifier: 400, applicationName: "Messages"),
    ]
    let fixture = try makeFixture(windows: initialWindows)
    defer { fixture.cleanUp() }

    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }
    fixture.model.selectedLayout = .threeColumns
    fixture.model.selectedWindowIDs = Array(initialWindows.prefix(3).map(\.id))

    fixture.windowController.windows = [initialWindows[0], initialWindows[1], initialWindows[3]]
    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }

    #expect(fixture.model.selectedWindowIDs == Array(initialWindows.prefix(2).map(\.id)))
    #expect(!fixture.model.canApplySelection)
    #expect(fixture.model.statusMessage == "A selected window is no longer available.")
    #expect(fixture.model.statusIsError)
  }

  @Test
  func savedRecipeTrimsItsNameAndPersistsTheCurrentSelection() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    fixture.model.refreshWindows()
    await waitWhile { fixture.model.isRefreshing }

    fixture.model.saveRecipe(named: "  Work  ")

    #expect(fixture.recipeStore.recipes.count == 1)
    #expect(fixture.recipeStore.recipes.first?.name == "Work")
    #expect(fixture.recipeStore.recipes.first?.slots.map(\.bundleIdentifier) == [
      "com.apple.Safari", "com.apple.Notes",
    ])
    #expect(fixture.model.statusMessage == "Saved “Work”.")
    #expect(!fixture.model.statusIsError)
  }

  func makeFixture(
    windows: [WindowDescriptor] = Self.makeWindows(),
    arrangementResult: ArrangementResult = ArrangementResult(arrangedCount: 0, failures: []),
    undoResult: ArrangementResult = ArrangementResult(
      arrangedCount: 0,
      failures: ["Nothing to undo"]
    ),
    blockFirstDiscovery: Bool = false
  ) throws -> ModelFixture {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let recipeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).json")
    let historyURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).json")
    let recipeStore = RecipeStore(fileURL: recipeURL)
    let historyStore = ArrangementHistoryStore(fileURL: historyURL)
    let windowController = WindowControllerStub(
      windows: windows,
      arrangementResult: arrangementResult,
      undoResult: undoResult,
      blockFirstDiscovery: blockFirstDiscovery
    )
    let picker = PickerPresenterSpy()
    let launchAtLoginService = AppModelLaunchAtLoginServiceStub()
    let model = AppModel(
      accessibilityClient: windowController,
      recipeStore: recipeStore,
      historyStore: historyStore,
      launchAtLogin: LaunchAtLoginController(service: launchAtLoginService),
      pickerPanelCoordinator: picker,
      defaults: defaults
    )
    return ModelFixture(
      model: model,
      windowController: windowController,
      picker: picker,
      recipeStore: recipeStore,
      launchAtLoginService: launchAtLoginService,
      defaults: defaults,
      suiteName: suiteName,
      recipeURL: recipeURL,
      historyURL: historyURL
    )
  }

  func waitWhile(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 where condition() {
      await Task.yield()
    }
    #expect(!condition())
  }

  private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 where !condition() {
      await Task.yield()
    }
    #expect(condition())
  }

  private static func makeWindows() -> [WindowDescriptor] {
    [
      WindowDescriptor(
        id: UUID(),
        processIdentifier: 100,
        applicationName: "Safari",
        bundleIdentifier: "com.apple.Safari",
        title: "Browser",
        icon: NSImage(),
        frame: CGRect(x: 0, y: 0, width: 500, height: 800),
        isFocused: true
      ),
      WindowDescriptor(
        id: UUID(),
        processIdentifier: 200,
        applicationName: "Notes",
        bundleIdentifier: "com.apple.Notes",
        title: "Notes",
        icon: NSImage(),
        frame: CGRect(x: 500, y: 0, width: 500, height: 800),
        isFocused: false
      ),
    ]
  }

  private static func makeSameApplicationWindows() -> [WindowDescriptor] {
    makeWindows().map {
      WindowDescriptor(
        id: $0.id,
        processIdentifier: 100,
        applicationName: "Safari",
        bundleIdentifier: "com.apple.Safari",
        title: $0.title,
        icon: $0.icon,
        frame: $0.frame,
        isFocused: $0.isFocused
      )
    }
  }

  private static func makeWindow(
    processIdentifier: pid_t,
    applicationName: String
  ) -> WindowDescriptor {
    WindowDescriptor(
      id: UUID(),
      processIdentifier: processIdentifier,
      applicationName: applicationName,
      bundleIdentifier: "com.example.\(applicationName.lowercased())",
      title: applicationName,
      icon: NSImage(),
      frame: CGRect(x: 0, y: 0, width: 500, height: 800),
      isFocused: false
    )
  }
}

@MainActor
struct ModelFixture {
  let model: AppModel
  let windowController: WindowControllerStub
  let picker: PickerPresenterSpy
  let recipeStore: RecipeStore
  let launchAtLoginService: AppModelLaunchAtLoginServiceStub
  let defaults: UserDefaults
  let suiteName: String
  let recipeURL: URL
  let historyURL: URL

  func cleanUp() {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: recipeURL)
    try? FileManager.default.removeItem(at: historyURL)
  }
}

@MainActor
final class AppModelLaunchAtLoginServiceStub: LaunchAtLoginServicing {
  private(set) var statusRequestCount = 0

  var status: SMAppService.Status {
    statusRequestCount += 1
    return .notRegistered
  }

  func register() throws {}
  func unregister() throws {}
  func openSystemSettingsLoginItems() {}
}

@MainActor
final class WindowControllerStub: WindowControlling {
  let hasPermission = true
  var hasUndo = true
  var windows: [WindowDescriptor]
  private(set) var discoverCallCount = 0
  private(set) var maximumConcurrentDiscoveries = 0
  private(set) var arrangeCallCount = 0
  private(set) var arrangedWindowIDs: [UUID] = []
  private(set) var arrangedGap: CGFloat?
  private(set) var broughtArrangedWindowsForward: Bool?

  private let arrangementResult: ArrangementResult
  private let undoResult: ArrangementResult
  private let blockFirstDiscovery: Bool
  private var concurrentDiscoveries = 0
  private var firstDiscoveryContinuation: CheckedContinuation<Void, Never>?

  init(
    windows: [WindowDescriptor],
    arrangementResult: ArrangementResult,
    undoResult: ArrangementResult,
    blockFirstDiscovery: Bool
  ) {
    self.windows = windows
    self.arrangementResult = arrangementResult
    self.undoResult = undoResult
    self.blockFirstDiscovery = blockFirstDiscovery
  }

  func requestPermission() -> Bool { hasPermission }
  func openAccessibilitySettings() {}

  func discoverWindows(recentProcessIdentifiers: [pid_t]) async -> [WindowDescriptor] {
    discoverCallCount += 1
    concurrentDiscoveries += 1
    maximumConcurrentDiscoveries = max(maximumConcurrentDiscoveries, concurrentDiscoveries)
    if blockFirstDiscovery, discoverCallCount == 1 {
      await withCheckedContinuation { continuation in
        firstDiscoveryContinuation = continuation
      }
    }
    concurrentDiscoveries -= 1
    return windows
  }

  func releaseFirstDiscovery() {
    firstDiscoveryContinuation?.resume()
    firstDiscoveryContinuation = nil
  }

  func arrange(
    windowIDs: [UUID],
    layout: SplitLayout,
    ratio: SplitRatio,
    gap: CGFloat,
    bringWindowsForward: Bool
  ) async -> ArrangementResult {
    arrangeCallCount += 1
    arrangedWindowIDs = windowIDs
    arrangedGap = gap
    broughtArrangedWindowsForward = bringWindowsForward
    return arrangementResult
  }

  func undo() async -> ArrangementResult {
    undoResult
  }
}

@MainActor
final class PickerPresenterSpy: PickerPresenting {
  private(set) var dismissCount = 0
  private(set) var showCount = 0

  func show(model: AppModel) { showCount += 1 }
  func dismiss() { dismissCount += 1 }
}
