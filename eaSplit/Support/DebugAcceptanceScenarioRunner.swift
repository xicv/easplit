#if DEBUG
import Foundation

struct DebugAcceptanceCheck: Codable, Equatable, Sendable {
  let name: String
  let passed: Bool
  let detail: String
}

struct DebugAcceptanceReport: Codable, Equatable, Sendable {
  let passed: Bool
  let checks: [DebugAcceptanceCheck]

  init(checks: [DebugAcceptanceCheck]) {
    self.checks = checks
    passed = !checks.isEmpty && checks.allSatisfy(\.passed)
  }
}

@MainActor
final class DebugAcceptanceScenarioRunner {
  static let fixtureBundleIdentifier = "com.xicao.easplit.acceptance-fixture"

  private let model: AppModel

  init(model: AppModel) {
    self.model = model
  }

  func run() async -> DebugAcceptanceReport {
    var checks: [DebugAcceptanceCheck]
    model.refreshWindows()
    guard await waitForIdle() else {
      return DebugAcceptanceReport(checks: [
        DebugAcceptanceCheck(
          name: "Fixture discovery",
          passed: false,
          detail: "Window discovery did not finish."
        )
      ])
    }

    let fixtureWindows = model.windows.filter {
      $0.bundleIdentifier == Self.fixtureBundleIdentifier
    }
    let discovery = fixtureDiscovery(from: fixtureWindows)
    checks = [discovery.check]
    guard let windowIDs = discovery.windowIDs else {
      return DebugAcceptanceReport(checks: checks)
    }

    checks.append(contentsOf: await exerciseSuggestion(windowIDs: windowIDs))
    checks.append(contentsOf: await exerciseLayoutMatrix(windowIDs: windowIDs))
    return DebugAcceptanceReport(checks: checks)
  }

  private func fixtureDiscovery(
    from fixtureWindows: [WindowDescriptor]
  ) -> (check: DebugAcceptanceCheck, windowIDs: [UUID]?) {
    let expectedTitles = ["Browser Fixture", "Chat Fixture"]
    let discoveredTitles = fixtureWindows.map(\.title).sorted()
    let windowIDs = expectedTitles.compactMap { title in
      fixtureWindows.first { $0.title == title }?.id
    }
    let passed = discoveredTitles == expectedTitles.sorted() && windowIDs.count == 2
    return (
      DebugAcceptanceCheck(
        name: "Fixture discovery",
        passed: passed,
        detail: "Discovered: \(discoveredTitles.joined(separator: ", "))"
      ),
      passed ? windowIDs : nil
    )
  }

  private func exerciseSuggestion(windowIDs: [UUID]) async -> [DebugAcceptanceCheck] {
    var checks: [DebugAcceptanceCheck] = []
    configure(
      layout: .twoColumns,
      ratio: .equal,
      gap: 8,
      windowIDs: windowIDs
    )
    let firstUsePassed = await applyCurrentSelection()
    let firstUseDidNotSuggest = model.suggestion == nil
    _ = await restoreWindows()

    let secondUsePassed = await applyCurrentSelection()
    let suggestionPassed: Bool
    if case .frequentlyUsed(let count) = model.suggestion?.reason {
      suggestionPassed = count == 2 && model.suggestion?.windowIDs == windowIDs
    } else {
      suggestionPassed = false
    }
    checks.append(
      DebugAcceptanceCheck(
        name: "Frequent suggestion",
        passed: firstUsePassed && firstUseDidNotSuggest && secondUsePassed && suggestionPassed,
        detail: suggestionPassed
          ? "The second successful use produced the expected suggestion."
          : "The expected suggestion was not produced after two successful uses."
      )
    )
    _ = await restoreWindows()

    model.applySuggestion()
    let suggestionApplicationPassed = await waitForIdle() && !model.statusIsError
    let suggestionApplicationDetail = model.statusMessage ?? "No status was reported."
    checks.append(
      DebugAcceptanceCheck(
        name: "Apply suggestion",
        passed: suggestionApplicationPassed,
        detail: suggestionApplicationDetail
      )
    )
    checks.append(await primaryFocusCheck(windowID: windowIDs[0]))
    _ = await restoreWindows()

    model.suppressSuggestion()
    model.refreshWindows()
    let suppressionPassed = await waitForIdle() && model.suggestion == nil
      && !model.statusIsError
    checks.append(
      DebugAcceptanceCheck(
        name: "Suppress suggestion",
        passed: suppressionPassed,
        detail: suppressionPassed
          ? "The suggestion stayed hidden after refresh."
          : "The suppressed suggestion returned after refresh."
      )
    )

    return checks
  }

  private func primaryFocusCheck(windowID: UUID) async -> DebugAcceptanceCheck {
    model.refreshWindows()
    let refreshPassed = await waitForIdle()
    let primaryWindow = model.windows.first { $0.id == windowID }
    let passed = refreshPassed && primaryWindow?.isFocused == true
    return DebugAcceptanceCheck(
      name: "Primary window focus",
      passed: passed,
      detail: passed
        ? "Slot 1 received keyboard focus after the split."
        : "Slot 1 was not the focused window after the split."
    )
  }

  private func exerciseLayoutMatrix(windowIDs: [UUID]) async -> [DebugAcceptanceCheck] {
    var checks: [DebugAcceptanceCheck] = []
    for layout in [SplitLayout.twoColumns, .twoRows] {
      for ratio in [SplitRatio.equal, .leading] {
        for gap in [0.0, 8.0] {
          configure(layout: layout, ratio: ratio, gap: gap, windowIDs: windowIDs)
          let arrangementPassed = await applyCurrentSelection()
          let arrangementDetail = model.statusMessage ?? "No arrangement status was reported."
          let undoPassed = await restoreWindows()
          checks.append(
            DebugAcceptanceCheck(
              name: "Layout \(layout.rawValue) \(ratio.rawValue) gap \(Int(gap))",
              passed: arrangementPassed && undoPassed,
              detail: arrangementPassed && undoPassed
                ? "Arrangement and undo succeeded."
                : arrangementDetail
            )
          )
        }
      }
    }
    return checks
  }

  private func configure(
    layout: SplitLayout,
    ratio: SplitRatio,
    gap: Double,
    windowIDs: [UUID]
  ) {
    model.selectedLayout = layout
    model.selectedRatio = ratio
    model.edgeToEdgeWindows = gap == 0
    model.gap = gap
    model.selectedWindowIDs = windowIDs
  }

  private func applyCurrentSelection() async -> Bool {
    model.applySelection()
    return await waitForIdle() && !model.statusIsError
  }

  private func restoreWindows() async -> Bool {
    model.undo()
    return await waitForIdle() && !model.statusIsError
  }

  private func waitForIdle() async -> Bool {
    for _ in 0..<500 {
      if !model.isRefreshing && !model.isArranging {
        return true
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }
}
#endif
