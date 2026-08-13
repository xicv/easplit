import AppKit
import Testing
@testable import eaSplit

@Suite(.serialized)
@MainActor
struct ApplicationVisibilityControllerTests {
  @Test
  func focusSplitHidesOnlyDistinctVisibleUnselectedApplications() {
    let selected = RunningApplicationStub(processIdentifier: 100, name: "Safari")
    let other = RunningApplicationStub(processIdentifier: 200, name: "Notes")
    let alreadyHidden = RunningApplicationStub(
      processIdentifier: 300,
      name: "Calendar",
      isHidden: true
    )
    let finder = RunningApplicationStub(
      processIdentifier: 400,
      name: "Finder",
      bundleIdentifier: "com.apple.finder"
    )
    let terminated = RunningApplicationStub(
      processIdentifier: 500,
      name: "Preview",
      isTerminated: true
    )
    let ownApplication = RunningApplicationStub(processIdentifier: 999, name: "eaSplit")
    let applications = [selected, other, alreadyHidden, finder, terminated, ownApplication]
    let controller = makeController(applications: applications, currentProcessIdentifier: 999)
    let candidates = [
      makeWindow(processIdentifier: 100, applicationName: "Safari"),
      makeWindow(processIdentifier: 200, applicationName: "Notes"),
      makeWindow(processIdentifier: 200, applicationName: "Notes"),
      makeWindow(processIdentifier: 300, applicationName: "Calendar"),
      makeWindow(processIdentifier: 400, applicationName: "Finder"),
      makeWindow(processIdentifier: 500, applicationName: "Preview"),
      makeWindow(processIdentifier: 999, applicationName: "eaSplit"),
    ]

    _ = controller.prepareForArrangement(selectedProcessIdentifiers: [100])
    let result = controller.completeArrangement(
      selectedProcessIdentifiers: [100],
      candidates: candidates,
      hideOtherApplications: true
    )

    #expect(result.changedCount == 1)
    #expect(result.warnings.isEmpty)
    #expect(other.hideCallCount == 1)
    #expect(other.isHidden)
    #expect(alreadyHidden.hideCallCount == 0)
    #expect(finder.hideCallCount == 0)
    #expect(terminated.hideCallCount == 0)
    #expect(ownApplication.hideCallCount == 0)
    #expect(controller.hasUndo)
  }

  @Test
  func undoRestoresOnlyVisibilityChangedByTheLatestSplit() {
    let first = RunningApplicationStub(processIdentifier: 100, name: "Safari")
    let second = RunningApplicationStub(processIdentifier: 200, name: "Notes")
    let third = RunningApplicationStub(processIdentifier: 300, name: "Calendar")
    let fourth = RunningApplicationStub(processIdentifier: 400, name: "Preview")
    let applications = [first, second, third, fourth]
    let controller = makeController(applications: applications)
    let candidates = applications.map {
      makeWindow(
        processIdentifier: $0.processIdentifier,
        applicationName: $0.localizedName ?? "Application"
      )
    }

    _ = controller.prepareForArrangement(selectedProcessIdentifiers: [100, 200])
    _ = controller.completeArrangement(
      selectedProcessIdentifiers: [100, 200],
      candidates: candidates,
      hideOtherApplications: true
    )
    #expect(third.isHidden)
    #expect(fourth.isHidden)

    _ = controller.prepareForArrangement(selectedProcessIdentifiers: [100, 300])
    _ = controller.completeArrangement(
      selectedProcessIdentifiers: [100, 300],
      candidates: candidates,
      hideOtherApplications: true
    )
    #expect(second.isHidden)
    #expect(!third.isHidden)
    #expect(fourth.isHidden)

    let result = controller.undo()

    #expect(result.changedCount == 2)
    #expect(!second.isHidden)
    #expect(third.isHidden)
    #expect(fourth.isHidden)
    #expect(!controller.hasUndo)
  }

  @Test
  func cancelledArrangementRehidesAnApplicationPreparedForSelection() {
    let selected = RunningApplicationStub(
      processIdentifier: 100,
      name: "Safari",
      isHidden: true
    )
    let controller = makeController(applications: [selected])

    let preparation = controller.prepareForArrangement(
      selectedProcessIdentifiers: [selected.processIdentifier]
    )
    #expect(preparation.changedCount == 1)
    #expect(!selected.isHidden)

    let cancellation = controller.cancelArrangement()

    #expect(cancellation.changedCount == 1)
    #expect(selected.isHidden)
    #expect(!controller.hasUndo)
  }

  @Test
  func failedHideIsReportedAndIsNotAddedToUndo() {
    let selected = RunningApplicationStub(processIdentifier: 100, name: "Safari")
    let other = RunningApplicationStub(processIdentifier: 200, name: "Notes")
    other.hideSucceeds = false
    let controller = makeController(applications: [selected, other])

    _ = controller.prepareForArrangement(selectedProcessIdentifiers: [100])
    let result = controller.completeArrangement(
      selectedProcessIdentifiers: [100],
      candidates: [
        makeWindow(processIdentifier: 100, applicationName: "Safari"),
        makeWindow(processIdentifier: 200, applicationName: "Notes"),
      ],
      hideOtherApplications: true
    )

    #expect(result.changedCount == 0)
    #expect(result.warnings == ["Notes could not be hidden"])
    #expect(!controller.hasUndo)
  }

  @Test
  func failedUndoRemainsAvailableForRetry() {
    let selected = RunningApplicationStub(processIdentifier: 100, name: "Safari")
    let other = RunningApplicationStub(processIdentifier: 200, name: "Notes")
    let controller = makeController(applications: [selected, other])
    _ = controller.prepareForArrangement(selectedProcessIdentifiers: [100])
    _ = controller.completeArrangement(
      selectedProcessIdentifiers: [100],
      candidates: [
        makeWindow(processIdentifier: 100, applicationName: "Safari"),
        makeWindow(processIdentifier: 200, applicationName: "Notes"),
      ],
      hideOtherApplications: true
    )
    other.unhideSucceeds = false

    let failedUndo = controller.undo()

    #expect(failedUndo.warnings == ["Notes could not be shown"])
    #expect(controller.hasUndo)

    other.unhideSucceeds = true
    let successfulUndo = controller.undo()

    #expect(successfulUndo.changedCount == 1)
    #expect(successfulUndo.warnings.isEmpty)
    #expect(!controller.hasUndo)
  }

  @Test
  func acceptedHideCanBeUndoneBeforeTheHiddenStateUpdates() {
    let selected = RunningApplicationStub(processIdentifier: 100, name: "Safari")
    let other = RunningApplicationStub(processIdentifier: 200, name: "Notes")
    other.updatesVisibilityOnRequest = false
    let controller = makeController(applications: [selected, other])
    _ = controller.prepareForArrangement(selectedProcessIdentifiers: [100])
    _ = controller.completeArrangement(
      selectedProcessIdentifiers: [100],
      candidates: [
        makeWindow(processIdentifier: 100, applicationName: "Safari"),
        makeWindow(processIdentifier: 200, applicationName: "Notes"),
      ],
      hideOtherApplications: true
    )

    #expect(!other.isHidden)
    let result = controller.undo()

    #expect(result.changedCount == 1)
    #expect(other.unhideCallCount == 1)
    #expect(!controller.hasUndo)
  }

  private func makeController(
    applications: [RunningApplicationStub],
    currentProcessIdentifier: pid_t = 999
  ) -> ApplicationVisibilityController {
    let applicationsByProcessIdentifier = Dictionary(
      uniqueKeysWithValues: applications.map { ($0.processIdentifier, $0) }
    )
    return ApplicationVisibilityController(
      applicationProvider: { applicationsByProcessIdentifier[$0] },
      currentProcessIdentifier: currentProcessIdentifier
    )
  }

  private func makeWindow(
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
      frame: .zero,
      isFocused: false
    )
  }
}

@MainActor
private final class RunningApplicationStub: RunningApplicationAccessing {
  let processIdentifier: pid_t
  let bundleIdentifier: String?
  let localizedName: String?
  var isTerminated: Bool
  var isHidden: Bool
  var hideSucceeds = true
  var unhideSucceeds = true
  var updatesVisibilityOnRequest = true
  private(set) var hideCallCount = 0
  private(set) var unhideCallCount = 0

  init(
    processIdentifier: pid_t,
    name: String,
    bundleIdentifier: String? = nil,
    isTerminated: Bool = false,
    isHidden: Bool = false
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier ?? "com.example.\(name.lowercased())"
    localizedName = name
    self.isTerminated = isTerminated
    self.isHidden = isHidden
  }

  func hide() -> Bool {
    hideCallCount += 1
    if hideSucceeds, updatesVisibilityOnRequest { isHidden = true }
    return hideSucceeds
  }

  func unhide() -> Bool {
    unhideCallCount += 1
    if unhideSucceeds, updatesVisibilityOnRequest { isHidden = false }
    return unhideSucceeds
  }
}
