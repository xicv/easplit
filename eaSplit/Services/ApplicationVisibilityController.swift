import AppKit

struct ApplicationVisibilityResult: Sendable {
  let changedCount: Int
  let warnings: [String]

  static let unchanged = ApplicationVisibilityResult(changedCount: 0, warnings: [])
}

@MainActor
protocol ApplicationVisibilityControlling: AnyObject {
  var hasUndo: Bool { get }

  func prepareForArrangement(
    selectedProcessIdentifiers: Set<pid_t>
  ) -> ApplicationVisibilityResult
  func completeArrangement(
    selectedProcessIdentifiers: Set<pid_t>,
    candidates: [WindowDescriptor],
    hideOtherApplications: Bool
  ) -> ApplicationVisibilityResult
  func cancelArrangement() -> ApplicationVisibilityResult
  func undo() -> ApplicationVisibilityResult
}

@MainActor
protocol RunningApplicationAccessing: AnyObject {
  var processIdentifier: pid_t { get }
  var bundleIdentifier: String? { get }
  var localizedName: String? { get }
  var isTerminated: Bool { get }
  var isHidden: Bool { get }

  func hide() -> Bool
  func unhide() -> Bool
}

@MainActor
final class ApplicationVisibilityController: ApplicationVisibilityControlling {
  typealias ApplicationProvider = @MainActor (pid_t) -> (any RunningApplicationAccessing)?

  private struct Transaction {
    var applicationsToUnhide: [any RunningApplicationAccessing] = []
    var applicationsToRehide: [any RunningApplicationAccessing] = []

    var isEmpty: Bool {
      applicationsToUnhide.isEmpty && applicationsToRehide.isEmpty
    }
  }

  private let applicationProvider: ApplicationProvider
  private let currentProcessIdentifier: pid_t
  private var transaction = Transaction()

  init(
    applicationProvider: @escaping ApplicationProvider = { processIdentifier in
      NSRunningApplicationAdapter(processIdentifier: processIdentifier)
    },
    currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
  ) {
    self.applicationProvider = applicationProvider
    self.currentProcessIdentifier = currentProcessIdentifier
  }

  var hasUndo: Bool {
    !transaction.isEmpty
  }

  func prepareForArrangement(
    selectedProcessIdentifiers: Set<pid_t>
  ) -> ApplicationVisibilityResult {
    transaction = Transaction()
    var changedCount = 0
    var warnings: [String] = []

    for processIdentifier in selectedProcessIdentifiers.sorted() {
      guard
        let application = applicationProvider(processIdentifier),
        !application.isTerminated,
        application.isHidden
      else { continue }

      if application.unhide() {
        transaction.applicationsToRehide.append(application)
        changedCount += 1
      } else {
        warnings.append("\(name(of: application)) could not be shown")
      }
    }

    return ApplicationVisibilityResult(changedCount: changedCount, warnings: warnings)
  }

  func completeArrangement(
    selectedProcessIdentifiers: Set<pid_t>,
    candidates: [WindowDescriptor],
    hideOtherApplications: Bool
  ) -> ApplicationVisibilityResult {
    guard hideOtherApplications else { return .unchanged }

    var seenProcessIdentifiers = Set<pid_t>()
    var changedCount = 0
    var warnings: [String] = []

    for candidate in candidates {
      let processIdentifier = candidate.processIdentifier
      guard
        seenProcessIdentifiers.insert(processIdentifier).inserted,
        processIdentifier != currentProcessIdentifier,
        !selectedProcessIdentifiers.contains(processIdentifier),
        let application = applicationProvider(processIdentifier),
        application.bundleIdentifier != "com.apple.finder",
        !application.isTerminated,
        !application.isHidden
      else { continue }

      if application.hide() {
        transaction.applicationsToUnhide.append(application)
        changedCount += 1
      } else {
        warnings.append("\(name(of: application)) could not be hidden")
      }
    }

    return ApplicationVisibilityResult(changedCount: changedCount, warnings: warnings)
  }

  func cancelArrangement() -> ApplicationVisibilityResult {
    let result = restoreApplications(
      transaction.applicationsToRehide,
      targetHiddenState: true
    )
    transaction = Transaction(
      applicationsToRehide: result.failedApplications
    )
    return ApplicationVisibilityResult(
      changedCount: result.changedCount,
      warnings: result.warnings
    )
  }

  func undo() -> ApplicationVisibilityResult {
    let unhideResult = restoreApplications(
      transaction.applicationsToUnhide,
      targetHiddenState: false
    )
    let rehideResult = restoreApplications(
      transaction.applicationsToRehide,
      targetHiddenState: true
    )

    transaction = Transaction(
      applicationsToUnhide: unhideResult.failedApplications,
      applicationsToRehide: rehideResult.failedApplications
    )
    return ApplicationVisibilityResult(
      changedCount: unhideResult.changedCount + rehideResult.changedCount,
      warnings: unhideResult.warnings + rehideResult.warnings
    )
  }

  private func restoreApplications(
    _ applications: [any RunningApplicationAccessing],
    targetHiddenState: Bool
  ) -> RestorationResult {
    var changedCount = 0
    var warnings: [String] = []
    var failedApplications: [any RunningApplicationAccessing] = []

    for application in applications where !application.isTerminated {
      let succeeded = targetHiddenState ? application.hide() : application.unhide()
      if succeeded {
        changedCount += 1
      } else {
        let action = targetHiddenState ? "hidden" : "shown"
        warnings.append("\(name(of: application)) could not be \(action)")
        failedApplications.append(application)
      }
    }

    return RestorationResult(
      changedCount: changedCount,
      warnings: warnings,
      failedApplications: failedApplications
    )
  }

  private func name(of application: any RunningApplicationAccessing) -> String {
    application.localizedName ?? application.bundleIdentifier ?? "An application"
  }
}

@MainActor
private struct RestorationResult {
  let changedCount: Int
  let warnings: [String]
  let failedApplications: [any RunningApplicationAccessing]
}

@MainActor
private final class NSRunningApplicationAdapter: RunningApplicationAccessing {
  private let application: NSRunningApplication

  init?(processIdentifier: pid_t) {
    guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
      return nil
    }
    self.application = application
  }

  var processIdentifier: pid_t { application.processIdentifier }
  var bundleIdentifier: String? { application.bundleIdentifier }
  var localizedName: String? { application.localizedName }
  var isTerminated: Bool { application.isTerminated }
  var isHidden: Bool { application.isHidden }

  func hide() -> Bool { application.hide() }
  func unhide() -> Bool { application.unhide() }
}
