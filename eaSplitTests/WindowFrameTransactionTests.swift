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
  func applyRetriesWithSizeFirstWhenPositionFirstIsRejected() {
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
    #expect(accessor.mutations.prefix(2) == [.position, .size])
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
        == "the application kept 800×900 instead of 960×1080")
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
}

private final class FrameAccessorFake: @unchecked Sendable, WindowFrameAccessing {
  typealias Handle = Int

  enum Mutation {
    case position
    case size
  }

  private var frames: [Int: CGRect]
  private var rejectedPositionAttempts: Int
  private let maximumSize: CGSize?
  private let rejectedSizeHandles: Set<Int>
  private(set) var mutations: [Mutation] = []

  init(
    frames: [Int: CGRect],
    rejectedPositionAttempts: Int = 0,
    maximumSize: CGSize? = nil,
    rejectedSizeHandles: Set<Int> = []
  ) {
    self.frames = frames
    self.rejectedPositionAttempts = rejectedPositionAttempts
    self.maximumSize = maximumSize
    self.rejectedSizeHandles = rejectedSizeHandles
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
    frames[handle]?.origin = position
    return nil
  }

  func setSize(_ size: CGSize, for handle: Int) -> String? {
    mutations.append(.size)
    if rejectedSizeHandles.contains(handle) {
      return "size was rejected"
    }
    if let maximumSize {
      frames[handle]?.size = CGSize(
        width: min(size.width, maximumSize.width),
        height: min(size.height, maximumSize.height)
      )
    } else {
      frames[handle]?.size = size
    }
    return nil
  }

  func waitForWindowToSettle() {}
}
