#if DEBUG
import AppKit
import Foundation
import ServiceManagement
import Testing
@testable import eaSplit

@Suite(.serialized)
@MainActor
struct DebugAcceptanceScenarioTests {
  @Test
  func launchConfigurationRequiresAnAbsoluteReportPath() throws {
    let expectedURL = URL(fileURLWithPath: "/tmp/eaSplit-acceptance/report.json")

    let configuration = try #require(
      DebugAcceptanceLaunchConfiguration(arguments: [
        "eaSplit", "--acceptance-report", expectedURL.path,
      ])
    )

    #expect(configuration.reportURL == expectedURL)
    #expect(
      DebugAcceptanceLaunchConfiguration(arguments: [
        "eaSplit", "--acceptance-report", "relative.json",
      ]) == nil
    )
  }

  @Test
  func persistenceVerifierReloadsLearnedAndSuppressedState() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let historyURL = directory.appendingPathComponent("arrangement-history.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let signature = ArrangementSignature(
      recipe: SplitRecipe(
        name: "Acceptance",
        layout: .twoColumns,
        ratio: .equal,
        slots: [
          .init(
            bundleIdentifier: DebugAcceptanceScenarioRunner.fixtureBundleIdentifier,
            applicationName: "eaSplit Acceptance Fixture"
          ),
          .init(
            bundleIdentifier: DebugAcceptanceScenarioRunner.fixtureBundleIdentifier,
            applicationName: "eaSplit Acceptance Fixture"
          ),
        ]
      ),
      fallbackSpacing: .init(edgeToEdge: false, gap: 8)
    )
    let store = ArrangementHistoryStore(fileURL: historyURL)
    store.record(
      ArrangementEvent(signature: signature, performedAt: Date(), source: .manual)
    )
    store.record(
      ArrangementEvent(signature: signature, performedAt: Date(), source: .manual)
    )
    store.suppress(signature)

    let check = DebugAcceptancePersistenceVerifier().check(historyURL: historyURL)

    #expect(check.name == "Suggestion persistence")
    #expect(check.passed)
  }

  @Test
  func completeScenarioPassesEveryObservableCheck() async throws {
    let windows = [
      fixtureWindow(title: "Browser Fixture"),
      fixtureWindow(title: "Chat Fixture"),
    ]
    let controller = AcceptanceWindowControllerStub(windows: windows)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let defaultsName = "DebugAcceptanceScenarioTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer {
      defaults.removePersistentDomain(forName: defaultsName)
      try? FileManager.default.removeItem(at: directory)
    }
    let model = AppModel(
      accessibilityClient: controller,
      recipeStore: RecipeStore(fileURL: directory.appendingPathComponent("recipes.json")),
      historyStore: ArrangementHistoryStore(
        fileURL: directory.appendingPathComponent("arrangement-history.json")
      ),
      launchAtLogin: LaunchAtLoginController(service: AcceptanceLaunchAtLoginServiceStub()),
      pickerPanelCoordinator: AcceptancePickerPresenterStub(),
      defaults: defaults
    )

    let report = await DebugAcceptanceScenarioRunner(model: model).run()

    #expect(report.passed)
    #expect(report.checks.contains { $0.name == "Fixture discovery" && $0.passed })
    #expect(report.checks.contains { $0.name == "Frequent suggestion" && $0.passed })
    #expect(report.checks.contains { $0.name == "Apply suggestion" && $0.passed })
    #expect(report.checks.contains { $0.name == "Primary window focus" && $0.passed })
    #expect(report.checks.contains { $0.name == "Suppress suggestion" && $0.passed })
    #expect(report.checks.filter { $0.name.hasPrefix("Layout ") }.count == 8)
  }

  private func fixtureWindow(title: String) -> WindowDescriptor {
    WindowDescriptor(
      id: UUID(),
      processIdentifier: 900,
      applicationName: "eaSplit Acceptance Fixture",
      bundleIdentifier: DebugAcceptanceScenarioRunner.fixtureBundleIdentifier,
      title: title,
      icon: NSImage(),
      frame: CGRect(x: 100, y: 100, width: 500, height: 500),
      isFocused: title == "Browser Fixture"
    )
  }
}

@MainActor
private final class AcceptanceWindowControllerStub: WindowControlling {
  let hasPermission = true
  var hasUndo = false
  let windows: [WindowDescriptor]

  init(windows: [WindowDescriptor]) {
    self.windows = windows
  }

  func requestPermission() -> Bool { true }
  func openAccessibilitySettings() {}

  func discoverWindows(recentProcessIdentifiers: [pid_t]) async -> [WindowDescriptor] {
    windows
  }

  func arrange(
    windowIDs: [UUID],
    layout: SplitLayout,
    ratio: SplitRatio,
    gap: CGFloat,
    bringWindowsForward: Bool
  ) async -> ArrangementResult {
    hasUndo = true
    return ArrangementResult(arrangedCount: windowIDs.count, failures: [])
  }

  func undo() async -> ArrangementResult {
    hasUndo = false
    return ArrangementResult(arrangedCount: windows.count, failures: [])
  }
}

@MainActor
private final class AcceptancePickerPresenterStub: PickerPresenting {
  func show(model: AppModel) {}
  func dismiss() {}
}

@MainActor
private final class AcceptanceLaunchAtLoginServiceStub: LaunchAtLoginServicing {
  var status: SMAppService.Status { .notRegistered }
  func register() throws {}
  func unregister() throws {}
  func openSystemSettingsLoginItems() {}
}
#endif
