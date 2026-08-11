import CoreGraphics
import XCTest
@testable import eaSplit

final class LayoutEngineTests: XCTestCase {
  private let engine = LayoutEngine()
  private let display = CGRect(x: 0, y: 0, width: 1_000, height: 800)

  func testEqualColumnsFillVisibleFrameWithOuterAndInnerGaps() throws {
    let frames = try engine.frames(for: .twoColumns, in: display, ratio: .equal, gap: 10)

    XCTAssertEqual(frames, [
      CGRect(x: 10, y: 10, width: 485, height: 780),
      CGRect(x: 505, y: 10, width: 485, height: 780),
    ])
  }

  func testLeadingColumnsUseSixtyFortyRatio() throws {
    let frames = try engine.frames(for: .twoColumns, in: display, ratio: .leading, gap: 10)

    XCTAssertEqual(frames, [
      CGRect(x: 10, y: 10, width: 582, height: 780),
      CGRect(x: 602, y: 10, width: 388, height: 780),
    ])
  }

  func testRowsUseAccessibilityTopToBottomCoordinates() throws {
    let frames = try engine.frames(for: .twoRows, in: display, ratio: .equal, gap: 10)

    XCTAssertEqual(frames, [
      CGRect(x: 10, y: 10, width: 980, height: 385),
      CGRect(x: 10, y: 405, width: 980, height: 385),
    ])
  }

  func testThreeColumnsKeepRemainderInFinalColumn() throws {
    let frames = try engine.frames(for: .threeColumns, in: display, ratio: .equal, gap: 10)

    XCTAssertEqual(frames, [
      CGRect(x: 10, y: 10, width: 320, height: 780),
      CGRect(x: 340, y: 10, width: 320, height: 780),
      CGRect(x: 670, y: 10, width: 320, height: 780),
    ])
  }

  func testFocusLayoutSplitsTrailingColumnEvenly() throws {
    let frames = try engine.frames(for: .leadingWithStack, in: display, ratio: .leading, gap: 10)

    XCTAssertEqual(frames, [
      CGRect(x: 10, y: 10, width: 582, height: 780),
      CGRect(x: 602, y: 10, width: 388, height: 385),
      CGRect(x: 602, y: 405, width: 388, height: 385),
    ])
  }

  func testZeroGapLayoutsFillVisibleFrameEdgeToEdge() throws {
    XCTAssertEqual(
      try engine.frames(for: .twoColumns, in: display, ratio: .equal, gap: 0),
      [
        CGRect(x: 0, y: 0, width: 500, height: 800),
        CGRect(x: 500, y: 0, width: 500, height: 800),
      ]
    )

    XCTAssertEqual(
      try engine.frames(for: .twoRows, in: display, ratio: .equal, gap: 0),
      [
        CGRect(x: 0, y: 0, width: 1_000, height: 400),
        CGRect(x: 0, y: 400, width: 1_000, height: 400),
      ]
    )

    XCTAssertEqual(
      try engine.frames(for: .threeColumns, in: display, ratio: .equal, gap: 0),
      [
        CGRect(x: 0, y: 0, width: 333, height: 800),
        CGRect(x: 333, y: 0, width: 333, height: 800),
        CGRect(x: 666, y: 0, width: 334, height: 800),
      ]
    )

    XCTAssertEqual(
      try engine.frames(for: .leadingWithStack, in: display, ratio: .leading, gap: 0),
      [
        CGRect(x: 0, y: 0, width: 600, height: 800),
        CGRect(x: 600, y: 0, width: 400, height: 400),
        CGRect(x: 600, y: 400, width: 400, height: 400),
      ]
    )
  }

  func testInvalidBoundsAreRejected() {
    XCTAssertThrowsError(
      try engine.frames(for: .twoColumns, in: .zero, ratio: .equal, gap: 8)
    ) { error in
      XCTAssertEqual(error as? LayoutEngineError, .invalidBounds)
    }
  }
}
