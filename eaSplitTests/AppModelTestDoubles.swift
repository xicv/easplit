import AppKit
import Foundation
import ServiceManagement
@testable import eaSplit

@MainActor
struct ModelFixture {
  let model: AppModel
  let windowController: WindowControllerStub
  let applicationVisibilityController: ApplicationVisibilityControllerSpy
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
final class ApplicationVisibilityControllerSpy: ApplicationVisibilityControlling {
  var hasUndo = false
  private(set) var hiddenApplicationIDs: [pid_t] = []
  private(set) var completeCallCount = 0
  private(set) var cancelCallCount = 0
  private(set) var undoCallCount = 0

  func prepareForArrangement(
    selectedProcessIdentifiers: Set<pid_t>
  ) -> ApplicationVisibilityResult {
    .unchanged
  }

  func completeArrangement(
    selectedProcessIdentifiers: Set<pid_t>,
    candidates: [WindowDescriptor],
    hideOtherApplications: Bool
  ) -> ApplicationVisibilityResult {
    completeCallCount += 1
    guard hideOtherApplications else { return .unchanged }
    hiddenApplicationIDs = candidates
      .map(\.processIdentifier)
      .reduce(into: []) { identifiers, processIdentifier in
        guard
          !selectedProcessIdentifiers.contains(processIdentifier),
          !identifiers.contains(processIdentifier)
        else { return }
        identifiers.append(processIdentifier)
      }
    hasUndo = !hiddenApplicationIDs.isEmpty
    return ApplicationVisibilityResult(
      changedCount: hiddenApplicationIDs.count,
      warnings: []
    )
  }

  func cancelArrangement() -> ApplicationVisibilityResult {
    cancelCallCount += 1
    hasUndo = false
    return .unchanged
  }

  func undo() -> ApplicationVisibilityResult {
    undoCallCount += 1
    let count = hiddenApplicationIDs.count
    hiddenApplicationIDs = []
    hasUndo = false
    return ApplicationVisibilityResult(changedCount: count, warnings: [])
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
