#if DEBUG
import Foundation

struct DebugAcceptanceLaunchConfiguration: Equatable, Sendable {
  let reportURL: URL

  init?(arguments: [String]) {
    guard
      let flagIndex = arguments.firstIndex(of: "--acceptance-report"),
      arguments.indices.contains(flagIndex + 1)
    else { return nil }

    let path = arguments[flagIndex + 1]
    guard path.hasPrefix("/") else { return nil }
    reportURL = URL(fileURLWithPath: path).standardizedFileURL
  }
}

@MainActor
final class DebugAcceptanceLaunch {
  let model: AppModel

  private let configuration: DebugAcceptanceLaunchConfiguration
  private let defaults: UserDefaults
  private let defaultsName: String
  private let historyURL: URL

  init?(arguments: [String] = CommandLine.arguments) {
    guard let configuration = DebugAcceptanceLaunchConfiguration(arguments: arguments) else {
      return nil
    }

    self.configuration = configuration
    defaultsName = "com.xicao.easplit.debug.acceptance.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsName) else { return nil }
    self.defaults = defaults

    let dataDirectory = configuration.reportURL.deletingLastPathComponent()
      .appendingPathComponent("data", isDirectory: true)
    historyURL = dataDirectory.appendingPathComponent("arrangement-history.json")
    let windowController = DebugAcceptanceWindowController(
      base: AccessibilityWindowClient()
    )
    model = AppModel(
      accessibilityClient: windowController,
      recipeStore: RecipeStore(
        fileURL: dataDirectory.appendingPathComponent("recipes.json")
      ),
      historyStore: ArrangementHistoryStore(
        fileURL: historyURL
      ),
      defaults: defaults
    )
  }

  func run() async {
    let scenarioReport = await DebugAcceptanceScenarioRunner(model: model).run()
    let persistenceCheck = DebugAcceptancePersistenceVerifier().check(
      historyURL: historyURL
    )
    let report = DebugAcceptanceReport(
      checks: scenarioReport.checks + [persistenceCheck]
    )

    do {
      try FileManager.default.createDirectory(
        at: configuration.reportURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(report).write(to: configuration.reportURL, options: .atomic)
    } catch {
      AppLogger.performance.error(
        "Acceptance report could not be written: \(error.localizedDescription, privacy: .public)"
      )
    }

    defaults.removePersistentDomain(forName: defaultsName)
  }
}

@MainActor
struct DebugAcceptancePersistenceVerifier {
  func check(historyURL: URL) -> DebugAcceptanceCheck {
    let reloadedStore = ArrangementHistoryStore(fileURL: historyURL)
    let passed = reloadedStore.errorMessage == nil
      && reloadedStore.events.count >= 2
      && !reloadedStore.suppressedSignatures.isEmpty
    return DebugAcceptanceCheck(
      name: "Suggestion persistence",
      passed: passed,
      detail: passed
        ? "Learned and suppressed state survived a fresh store load."
        : "Learned or suppressed state did not survive a fresh store load."
    )
  }
}

@MainActor
private final class DebugAcceptanceWindowController: WindowControlling {
  private let base: any WindowControlling

  init(base: any WindowControlling) {
    self.base = base
  }

  var hasPermission: Bool { base.hasPermission }
  var hasUndo: Bool { base.hasUndo }

  func requestPermission() -> Bool {
    base.requestPermission()
  }

  func openAccessibilitySettings() {
    base.openAccessibilitySettings()
  }

  func discoverWindows(recentProcessIdentifiers: [pid_t]) async -> [WindowDescriptor] {
    await base.discoverWindows(recentProcessIdentifiers: recentProcessIdentifiers)
      .filter {
        $0.bundleIdentifier == DebugAcceptanceScenarioRunner.fixtureBundleIdentifier
      }
  }

  func arrange(
    windowIDs: [UUID],
    layout: SplitLayout,
    ratio: SplitRatio,
    gap: CGFloat,
    bringWindowsForward: Bool
  ) async -> ArrangementResult {
    await base.arrange(
      windowIDs: windowIDs,
      layout: layout,
      ratio: ratio,
      gap: gap,
      bringWindowsForward: bringWindowsForward
    )
  }

  func undo() async -> ArrangementResult {
    await base.undo()
  }
}
#endif
