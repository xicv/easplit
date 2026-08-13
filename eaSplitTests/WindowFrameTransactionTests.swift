import CoreGraphics
import Testing
@testable import eaSplit

@Suite
struct WindowFrameTransactionTests {
  @Test
  func successfulApplyCapturesTheOriginalFrame() {
    let original = CGRect(x: 40, y: 60, width: 700, height: 500)
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(frames: [1: original])
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcomes = transaction.apply([
      WindowFrameTarget(applicationName: "Safari", handle: 1, destination: destination)
    ])

    #expect(outcomes.count == 1)
    #expect(outcomes[0].originalFrame == original)
    #expect(outcomes[0].failure == nil)
    #expect(accessor.frame(of: 1) == destination)
  }

  @Test
  func applyUsesSizePositionSizeOrderForScreenConstrainedWindows() {
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 40, y: 60, width: 700, height: 500)]
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Safari", handle: 1, destination: destination)
    ])[0]

    #expect(outcome.failure == nil)
    #expect(accessor.mutations == [.size, .position, .size])
  }

  @Test
  func applyRetriesAfterPositionIsRejected() {
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 40, y: 60, width: 700, height: 500)],
      rejectedPositionAttempts: 1
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Safari", handle: 1, destination: destination)
    ])[0]

    #expect(outcome.failure == nil)
    #expect(accessor.frame(of: 1) == destination)
    #expect(accessor.mutations.suffix(3) == [.size, .position, .size])
  }

  @Test
  func applyReportsWhenAnApplicationClampsTheRequestedSize() {
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 40, y: 60, width: 700, height: 500)],
      maximumSize: CGSize(width: 800, height: 900)
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Terminal", handle: 1, destination: destination)
    ])[0]

    #expect(
      outcome.failure
        == "the window remained at (0, 0), 800×900; requested (0, 0), 960×1080")
  }

  @Test
  func applyReportsTheRejectedOperationAndFinalPosition() {
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 40, y: 60, width: 700, height: 500)],
      rejectedPositionAttempts: 100
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Safari", handle: 1, destination: destination)
    ])[0]

    #expect(
      outcome.failure
        == "position was rejected; the window remained at (40, 60), 960×1080; requested (0, 0), 960×1080"
    )
  }

  @Test
  func applyWaitsForAnAsynchronousWindowToSettleBeforeRetrying() {
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 40, y: 60, width: 700, height: 500)],
      settleAfterWaitCount: 3
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Browser", handle: 1, destination: destination)
    ])[0]

    #expect(outcome.failure == nil)
    #expect(accessor.frame(of: 1) == destination)
    #expect(accessor.mutations == [.size, .position, .size])
  }

  @Test
  func applyRetriesUntilASlowAccessibilityAnimationSettles() {
    let destination = CGRect(x: 0, y: 0, width: 1920, height: 2130)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 100, y: 100, width: 1000, height: 900)],
      settleAfterWaitCount: 37
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Browser", handle: 1, destination: destination)
    ])[0]

    #expect(outcome.failure == nil)
    #expect(accessor.frame(of: 1) == destination)
    #expect(accessor.mutations.count == 30)
  }

  @Test
  func applyRetriesAOnePointEdgeToEdgeNearMiss() {
    let destination = CGRect(x: 0, y: 30, width: 3_840, height: 2_130)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 100, y: 100, width: 1_000, height: 900)],
      onePointPositionOffsetAttempts: 1
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcome = transaction.apply([
      WindowFrameTarget(applicationName: "Browser", handle: 1, destination: destination)
    ])[0]

    #expect(outcome.failure == nil)
    #expect(accessor.frame(of: 1) == destination)
    #expect(accessor.mutations == [.size, .position, .size, .size, .position, .size])
  }

  @Test
  func applyOnlyCapturesUndoFramesThatCanBeRead() {
    let destination = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let accessor = FrameAccessorFake(
      frames: [1: CGRect(x: 40, y: 60, width: 700, height: 500)]
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcomes = transaction.apply([
      WindowFrameTarget(applicationName: "Safari", handle: 1, destination: destination),
      WindowFrameTarget(applicationName: "Closed", handle: 2, destination: destination),
    ])

    #expect(outcomes[0].originalFrame != nil)
    #expect(outcomes[1].originalFrame == nil)
    #expect(outcomes[1].failure == "the application did not report its final window size")
  }

  @Test
  func restoreReportsEachTargetIndependently() {
    let firstFrame = CGRect(x: 40, y: 60, width: 700, height: 500)
    let secondFrame = CGRect(x: 100, y: 120, width: 600, height: 400)
    let accessor = FrameAccessorFake(
      frames: [1: .zero, 2: .zero],
      rejectedSizeHandles: [2]
    )
    let transaction = WindowFrameTransaction(accessor: accessor)

    let outcomes = transaction.restore([
      WindowFrameTarget(applicationName: "Safari", handle: 1, destination: firstFrame),
      WindowFrameTarget(applicationName: "Terminal", handle: 2, destination: secondFrame),
    ])

    #expect(outcomes[0].1 == nil)
    #expect(outcomes[1].1 != nil)
    #expect(accessor.frame(of: 1) == firstFrame)
  }

  @Test
  func bringForwardFocusesEachWindowBeforeActivatingInReverseSlotOrder() {
    let accessor = ForegroundAccessorFake()
    let transaction = WindowForegroundTransaction(accessor: accessor)

    let failures = transaction.apply([
      WindowForegroundTarget(applicationName: "Safari", handle: 1),
      WindowForegroundTarget(applicationName: "Notes", handle: 2),
    ])

    #expect(failures.isEmpty)
    #expect(accessor.actions == [
      .focus(2), .activate(2), .raise(2),
      .focus(1), .activate(1), .raise(1),
    ])
  }

  @Test
  func secondArrangementMovesPreviouslySelectedApplicationBehindNewSelection() {
    let accessor = ForegroundAccessorFake(
      applicationByHandle: [1: "A", 2: "B", 3: "C"],
      applicationStack: ["A", "B", "C"]
    )
    let transaction = WindowForegroundTransaction(accessor: accessor)

    _ = transaction.apply([
      WindowForegroundTarget(applicationName: "A", handle: 1),
      WindowForegroundTarget(applicationName: "B", handle: 2),
    ])
    let failures = transaction.apply([
      WindowForegroundTarget(applicationName: "A", handle: 1),
      WindowForegroundTarget(applicationName: "C", handle: 3),
    ])

    #expect(failures.isEmpty)
    #expect(accessor.applicationStack == ["A", "C", "B"])
  }

  @Test
  func bringForwardSkipsWindowsThatWereNotArranged() {
    let accessor = ForegroundAccessorFake()
    let transaction = WindowForegroundTransaction(accessor: accessor)

    let failures = transaction.applySuccessful([
      WindowFrameOutcome(
        applicationName: "Safari",
        handle: 1,
        originalFrame: .zero,
        failure: nil
      ),
      WindowFrameOutcome(
        applicationName: "Notes",
        handle: 2,
        originalFrame: .zero,
        failure: "the window did not move"
      ),
    ])

    #expect(failures.isEmpty)
    #expect(accessor.actions == [.focus(1), .activate(1), .raise(1)])
  }

  @Test
  func bringForwardReportsRaiseAndPrimaryFocusFailures() {
    let accessor = ForegroundAccessorFake(
      raiseFailures: [2: "the window could not be brought forward"],
      focusFailures: [1: "the window could not receive keyboard focus"]
    )
    let transaction = WindowForegroundTransaction(accessor: accessor)

    let failures = transaction.apply([
      WindowForegroundTarget(applicationName: "Safari", handle: 1),
      WindowForegroundTarget(applicationName: "Notes", handle: 2),
    ])

    #expect(failures == [
      "Notes: the window could not be brought forward",
      "Safari: the window could not receive keyboard focus",
    ])
  }

  @Test
  func activationFailureIsReportedWithoutSkippingExactWindowActions() {
    let accessor = ForegroundAccessorFake(
      activationFailures: [2: "the owning application did not become active"]
    )
    let transaction = WindowForegroundTransaction(accessor: accessor)

    let failures = transaction.apply([
      WindowForegroundTarget(applicationName: "Safari", handle: 1),
      WindowForegroundTarget(applicationName: "Notes", handle: 2),
    ])

    #expect(failures == ["Notes: the owning application did not become active"])
    #expect(accessor.actions == [
      .focus(2), .activate(2), .raise(2),
      .focus(1), .activate(1), .raise(1),
    ])
  }
}

private final class ForegroundAccessorFake: @unchecked Sendable, WindowForegroundAccessing {
  enum Action: Equatable {
    case activate(Int)
    case raise(Int)
    case focus(Int)
  }

  private(set) var actions: [Action] = []
  private(set) var applicationStack: [String]
  private let activationFailures: [Int: String]
  private let raiseFailures: [Int: String]
  private let focusFailures: [Int: String]
  private let applicationByHandle: [Int: String]

  init(
    activationFailures: [Int: String] = [:],
    raiseFailures: [Int: String] = [:],
    focusFailures: [Int: String] = [:],
    applicationByHandle: [Int: String] = [1: "Safari", 2: "Notes"],
    applicationStack: [String] = ["Safari", "Notes"]
  ) {
    self.activationFailures = activationFailures
    self.raiseFailures = raiseFailures
    self.focusFailures = focusFailures
    self.applicationByHandle = applicationByHandle
    self.applicationStack = applicationStack
  }

  func activateApplication(owning handle: Int) -> String? {
    actions.append(.activate(handle))
    if let failure = activationFailures[handle] { return failure }
    guard let application = applicationByHandle[handle] else {
      return "the owning application is unavailable"
    }
    applicationStack.removeAll { $0 == application }
    applicationStack.insert(application, at: 0)
    return nil
  }

  func raise(_ handle: Int) -> String? {
    actions.append(.raise(handle))
    return raiseFailures[handle]
  }

  func focus(_ handle: Int) -> String? {
    actions.append(.focus(handle))
    return focusFailures[handle]
  }
}

private final class FrameAccessorFake: @unchecked Sendable, WindowFrameAccessing {
  typealias Handle = Int

  enum Mutation {
    case position
    case size
  }

  private var frames: [Int: CGRect]
  private var rejectedPositionAttempts: Int
  private var onePointPositionOffsetAttempts: Int
  private let maximumSize: CGSize?
  private let rejectedSizeHandles: Set<Int>
  private let settleAfterWaitCount: Int?
  private var pendingFrames: [Int: CGRect] = [:]
  private var waitCount = 0
  private(set) var mutations: [Mutation] = []

  init(
    frames: [Int: CGRect],
    rejectedPositionAttempts: Int = 0,
    onePointPositionOffsetAttempts: Int = 0,
    maximumSize: CGSize? = nil,
    rejectedSizeHandles: Set<Int> = [],
    settleAfterWaitCount: Int? = nil
  ) {
    self.frames = frames
    self.rejectedPositionAttempts = rejectedPositionAttempts
    self.onePointPositionOffsetAttempts = onePointPositionOffsetAttempts
    self.maximumSize = maximumSize
    self.rejectedSizeHandles = rejectedSizeHandles
    self.settleAfterWaitCount = settleAfterWaitCount
  }

  func frame(of handle: Int) -> CGRect? {
    frames[handle]
  }

  func setPosition(_ position: CGPoint, for handle: Int) -> String? {
    mutations.append(.position)
    if rejectedPositionAttempts > 0 {
      rejectedPositionAttempts -= 1
      return "position was rejected"
    }
    if onePointPositionOffsetAttempts > 0 {
      onePointPositionOffsetAttempts -= 1
      frames[handle]?.origin = CGPoint(x: position.x, y: position.y + 1)
      return nil
    }
    if settleAfterWaitCount == nil {
      frames[handle]?.origin = position
    } else {
      pendingFrames[handle, default: frames[handle] ?? .zero].origin = position
    }
    return nil
  }

  func setSize(_ size: CGSize, for handle: Int) -> String? {
    mutations.append(.size)
    if rejectedSizeHandles.contains(handle) {
      return "size was rejected"
    }
    if let maximumSize {
      updateSize(
        CGSize(
        width: min(size.width, maximumSize.width),
        height: min(size.height, maximumSize.height)
        ),
        for: handle
      )
    } else {
      updateSize(size, for: handle)
    }
    return nil
  }

  func waitForWindowToSettle() {
    waitCount += 1
    guard let settleAfterWaitCount, waitCount >= settleAfterWaitCount else { return }
    frames.merge(pendingFrames) { _, pending in pending }
    pendingFrames = [:]
  }

  private func updateSize(_ size: CGSize, for handle: Int) {
    if settleAfterWaitCount == nil {
      frames[handle]?.size = size
    } else {
      pendingFrames[handle, default: frames[handle] ?? .zero].size = size
    }
  }
}
