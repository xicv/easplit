import CoreGraphics
import Foundation

protocol WindowFrameAccessing: Sendable {
  associatedtype Handle: Sendable

  func frame(of handle: Handle) -> CGRect?
  func setPosition(_ position: CGPoint, for handle: Handle) -> String?
  func setSize(_ size: CGSize, for handle: Handle) -> String?
  func waitForWindowToSettle()
}

protocol WindowForegroundAccessing: Sendable {
  associatedtype Handle: Sendable

  func activateApplication(owning handle: Handle) -> String?
  func raise(_ handle: Handle) -> String?
  func focus(_ handle: Handle) -> String?
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

struct WindowForegroundTarget<Handle: Sendable>: Sendable {
  let applicationName: String
  let handle: Handle
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
    for _ in 0..<12 {
      let updates: [FrameUpdate] = [
        .size(frame.size), .position(frame.origin), .size(frame.size),
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

      for _ in 0..<4 {
        accessor.waitForWindowToSettle()
        if let actualFrame = accessor.frame(of: handle), framesMatch(actualFrame, frame) {
          return nil
        }
      }
    }

    guard let actualFrame = accessor.frame(of: handle) else {
      return lastError ?? "the application did not report its final window size"
    }
    let mismatch =
      "the window remained at \(formatted(actualFrame)); requested \(formatted(frame))"
    return lastError.map { "\($0); \(mismatch)" } ?? mismatch
  }

  private func framesMatch(
    _ actual: CGRect,
    _ expected: CGRect,
    tolerance: CGFloat = 0
  ) -> Bool {
    abs(actual.minX - expected.minX) <= tolerance
      && abs(actual.minY - expected.minY) <= tolerance
      && abs(actual.width - expected.width) <= tolerance
      && abs(actual.height - expected.height) <= tolerance
  }

  private func formatted(_ frame: CGRect) -> String {
    "(\(Int(frame.minX.rounded())), \(Int(frame.minY.rounded()))), "
      + "\(Int(frame.width.rounded()))×\(Int(frame.height.rounded()))"
  }
}

struct WindowForegroundTransaction<Accessor: WindowForegroundAccessing>: Sendable {
  let accessor: Accessor

  func applySuccessful(
    _ outcomes: [WindowFrameOutcome<Accessor.Handle>]
  ) -> [String] {
    apply(
      outcomes.compactMap { outcome in
        guard outcome.failure == nil else { return nil }
        return WindowForegroundTarget(
          applicationName: outcome.applicationName,
          handle: outcome.handle
        )
      }
    )
  }

  func apply(_ targets: [WindowForegroundTarget<Accessor.Handle>]) -> [String] {
    targets.reversed().flatMap { target in
      [
        accessor.focus(target.handle),
        accessor.activateApplication(owning: target.handle),
        accessor.raise(target.handle),
      ].compactMap { failure in
        failure.map { "\(target.applicationName): \($0)" }
      }
    }
  }
}

private enum FrameUpdate {
  case position(CGPoint)
  case size(CGSize)
}
