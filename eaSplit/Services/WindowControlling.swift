import CoreGraphics
import Foundation

@MainActor
protocol WindowControlling: AnyObject {
  var hasPermission: Bool { get }
  var hasUndo: Bool { get }

  @discardableResult
  func requestPermission() -> Bool
  func openAccessibilitySettings()
  func discoverWindows(recentProcessIdentifiers: [pid_t]) async -> [WindowDescriptor]
  func arrange(
    windowIDs: [UUID],
    layout: SplitLayout,
    ratio: SplitRatio,
    gap: CGFloat,
    bringWindowsForward: Bool
  ) async -> ArrangementResult
  func undo() async -> ArrangementResult
}
