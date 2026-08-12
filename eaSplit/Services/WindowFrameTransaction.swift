import CoreGraphics
import Foundation

protocol WindowFrameAccessing: Sendable {
  associatedtype Handle: Sendable

  func frame(of handle: Handle) -> CGRect?
  func setPosition(_ position: CGPoint, for handle: Handle) -> String?
  func setSize(_ size: CGSize, for handle: Handle) -> String?
  func waitForWindowToSettle()
}

struct WindowFrameTarget<Handle: Sendable>: Sendable {
  let applicationName: String
  let handle: Handle
  let destination: CGRect
}

struct WindowFrameOutcome<Handle: Sendable>: Sendable {
  let applicationName: String
  let handle: Handle
  let originalFrame: CGRect?
  let failure: String?
}

struct WindowFrameTransaction<Accessor: WindowFrameAccessing>: Sendable {
  let accessor: Accessor

  func apply(
    _ targets: [WindowFrameTarget<Accessor.Handle>]
  ) -> [WindowFrameOutcome<Accessor.Handle>] {
    targets.map { target in
      let originalFrame = accessor.frame(of: target.handle)
      let failure = setFrame(target.destination, for: target.handle)
      return WindowFrameOutcome(
        applicationName: target.applicationName,
        handle: target.handle,
        originalFrame: originalFrame,
        failure: failure
      )
    }
  }

  func restore(
    _ targets: [WindowFrameTarget<Accessor.Handle>]
  ) -> [(WindowFrameTarget<Accessor.Handle>, String?)] {
    targets.map { target in
      (target, setFrame(target.destination, for: target.handle))
    }
  }

  private func setFrame(_ frame: CGRect, for handle: Accessor.Handle) -> String? {
    var lastError: String?
    for attempt in 0..<2 {
      let updates: [FrameUpdate] =
        attempt == 0
        ? [.position(frame.origin), .size(frame.size), .position(frame.origin)]
        : [
          .size(frame.size), .position(frame.origin), .size(frame.size),
          .position(frame.origin),
        ]

      for update in updates {
        let failure: String?
        switch update {
        case .position(let position):
          failure = accessor.setPosition(position, for: handle)
        case .size(let size):
          failure = accessor.setSize(size, for: handle)
        }

        if let failure {
          lastError = failure
          break
        }
      }

      accessor.waitForWindowToSettle()
      if let actualFrame = accessor.frame(of: handle), framesMatch(actualFrame, frame) {
        return nil
      }
    }

    guard let actualFrame = accessor.frame(of: handle) else {
      return lastError ?? "the application did not report its final window size"
    }
    return
      "the application kept \(Int(actualFrame.width))×\(Int(actualFrame.height)) instead of \(Int(frame.width))×\(Int(frame.height))"
  }

  private func framesMatch(
    _ actual: CGRect,
    _ expected: CGRect,
    tolerance: CGFloat = 2
  ) -> Bool {
    abs(actual.minX - expected.minX) <= tolerance
      && abs(actual.minY - expected.minY) <= tolerance
      && abs(actual.width - expected.width) <= tolerance
      && abs(actual.height - expected.height) <= tolerance
  }
}

private enum FrameUpdate {
  case position(CGPoint)
  case size(CGSize)
}
