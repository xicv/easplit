import AppKit
import ApplicationServices

@MainActor
final class AccessibilityWindowClient: WindowControlling {
  private final class AXElement: @unchecked Sendable {
    let value: AXUIElement

    init(_ value: AXUIElement) {
      self.value = value
    }
  }

  private struct AXWindowFrameAccessor: WindowFrameAccessing {
    func frame(of handle: AXElement) -> CGRect? {
      AccessibilityWindowClient.frame(of: handle.value)
    }

    func setPosition(_ position: CGPoint, for handle: AXElement) -> String? {
      AXUIElementSetMessagingTimeout(handle.value, 0.5)
      var position = position
      guard let value = AXValueCreate(.cgPoint, &position) else {
        return "the requested frame could not be encoded"
      }
      let result = AXUIElementSetAttributeValue(
        handle.value,
        kAXPositionAttribute as CFString,
        value
      )
      return result == .success ? nil : AccessibilityWindowClient.description(for: result)
    }

    func setSize(_ size: CGSize, for handle: AXElement) -> String? {
      AXUIElementSetMessagingTimeout(handle.value, 0.5)
      var size = size
      guard let value = AXValueCreate(.cgSize, &size) else {
        return "the requested frame could not be encoded"
      }
      let result = AXUIElementSetAttributeValue(
        handle.value,
        kAXSizeAttribute as CFString,
        value
      )
      return result == .success ? nil : AccessibilityWindowClient.description(for: result)
    }

    func waitForWindowToSettle() {
      Thread.sleep(forTimeInterval: 0.015)
    }
  }

  private struct ApplicationCandidate: Sendable {
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
  }

  private struct ScreenSnapshot: Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
  }

  private struct WindowKey: Hashable, Sendable {
    let processIdentifier: pid_t
    let accessibilityHash: CFHashCode
  }

  private struct DiscoveredWindow: Sendable {
    let key: WindowKey
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
    let title: String
    let frame: CGRect
    let isFocused: Bool
    let element: AXElement
  }

  private struct WindowRecord {
    let descriptor: WindowDescriptor
    let element: AXElement
  }

  private struct UndoRecord: Sendable {
    let applicationName: String
    let element: AXElement
    let frame: CGRect
  }

  private var records: [UUID: WindowRecord] = [:]
  private var stableIdentifiers: [WindowKey: UUID] = [:]
  private var undoRecords: [UndoRecord] = []

  var hasPermission: Bool {
    AXIsProcessTrusted()
  }

  var hasUndo: Bool {
    !undoRecords.isEmpty
  }

  @discardableResult
  func requestPermission() -> Bool {
    AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    )
  }

  func openAccessibilitySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else { return }

    NSWorkspace.shared.open(url)
  }

  func discoverWindows(recentProcessIdentifiers: [pid_t]) async -> [WindowDescriptor] {
    guard hasPermission else {
      records = [:]
      stableIdentifiers = [:]
      return []
    }

    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    let rank = Dictionary(
      uniqueKeysWithValues: recentProcessIdentifiers.enumerated().map { ($1, $0) }
    )
    let applications = NSWorkspace.shared.runningApplications
      .filter {
        !$0.isTerminated
          && $0.processIdentifier != currentProcessIdentifier
          && $0.activationPolicy == .regular
      }
      .sorted {
        let leftRank = rank[$0.processIdentifier] ?? Int.max
        let rightRank = rank[$1.processIdentifier] ?? Int.max
        if leftRank != rightRank { return leftRank < rightRank }
        return ($0.localizedName ?? "") < ($1.localizedName ?? "")
      }

    let candidates = applications.map {
      ApplicationCandidate(
        processIdentifier: $0.processIdentifier,
        applicationName: $0.localizedName ?? "Application",
        bundleIdentifier: $0.bundleIdentifier
      )
    }
    let iconsByProcessIdentifier = Dictionary(
      uniqueKeysWithValues: applications.map { application in
        let applicationName = application.localizedName ?? "Application"
        let icon =
          application.icon
          ?? NSImage(systemSymbolName: "app", accessibilityDescription: applicationName)
          ?? NSImage()
        return (application.processIdentifier, icon)
      }
    )
    let screens = screenSnapshots()

    let rawWindows = await Self.discoverWindows(in: candidates, screens: screens)

    guard !Task.isCancelled, hasPermission else { return [] }

    var nextRecords: [UUID: WindowRecord] = [:]
    var nextStableIdentifiers: [WindowKey: UUID] = [:]
    var discovered: [WindowDescriptor] = []

    for window in rawWindows {
      let id = stableIdentifiers[window.key] ?? UUID()
      let descriptor = WindowDescriptor(
        id: id,
        processIdentifier: window.processIdentifier,
        applicationName: window.applicationName,
        bundleIdentifier: window.bundleIdentifier,
        title: window.title,
        icon: iconsByProcessIdentifier[window.processIdentifier] ?? NSImage(),
        frame: window.frame,
        isFocused: window.isFocused
      )

      nextStableIdentifiers[window.key] = id
      nextRecords[id] = WindowRecord(descriptor: descriptor, element: window.element)
      discovered.append(descriptor)
    }

    records = nextRecords
    stableIdentifiers = nextStableIdentifiers
    return discovered.sorted { left, right in
      let leftRank = rank[left.processIdentifier] ?? Int.max
      let rightRank = rank[right.processIdentifier] ?? Int.max
      if leftRank != rightRank { return leftRank < rightRank }
      if left.isFocused != right.isFocused { return left.isFocused }
      return left.displayTitle.localizedStandardCompare(right.displayTitle) == .orderedAscending
    }
  }

  func arrange(
    windowIDs: [UUID],
    layout: SplitLayout,
    ratio: SplitRatio,
    gap: CGFloat
  ) async -> ArrangementResult {
    guard windowIDs.count == layout.slotCount else {
      return ArrangementResult(
        arrangedCount: 0,
        failures: ["Choose exactly \(layout.slotCount) windows"]
      )
    }

    guard
      let firstID = windowIDs.first,
      let firstRecord = records[firstID],
      let targetFrame = visibleFrame(containing: firstRecord.descriptor.frame)
    else {
      return ArrangementResult(arrangedCount: 0, failures: ["The target display is unavailable"])
    }

    let destinationFrames: [CGRect]
    do {
      destinationFrames = try LayoutEngine().frames(
        for: layout,
        in: targetFrame,
        ratio: ratio,
        gap: gap
      )
    } catch {
      return ArrangementResult(arrangedCount: 0, failures: ["The display has invalid dimensions"])
    }

    let selectedRecords = windowIDs.compactMap { records[$0] }
    guard selectedRecords.count == destinationFrames.count else {
      return ArrangementResult(arrangedCount: 0, failures: ["One or more selected windows closed"])
    }

    let targets = zip(selectedRecords, destinationFrames).map { record, destination in
      WindowFrameTarget(
        applicationName: record.descriptor.applicationName,
        handle: record.element,
        destination: destination
      )
    }
    let outcomes = await Self.applyFrames(targets)

    undoRecords = outcomes.compactMap { outcome in
      guard let frame = outcome.originalFrame else { return nil }
      return UndoRecord(
        applicationName: outcome.applicationName,
        element: outcome.handle,
        frame: frame
      )
    }

    let failures = outcomes.compactMap { outcome in
      outcome.failure.map { "\(outcome.applicationName): \($0)" }
    }
    return ArrangementResult(
      arrangedCount: outcomes.count - failures.count,
      failures: failures
    )
  }

  func undo() async -> ArrangementResult {
    guard !undoRecords.isEmpty else {
      return ArrangementResult(arrangedCount: 0, failures: ["Nothing to undo"])
    }

    let recordsToRestore = undoRecords
    let outcomes = await Self.restoreFrames(recordsToRestore)

    undoRecords = outcomes.compactMap { record, failure in
      failure == nil ? nil : record
    }
    let failures = outcomes.compactMap { record, failure in
      failure.map { "\(record.applicationName): \($0)" }
    }
    return ArrangementResult(
      arrangedCount: outcomes.count - failures.count,
      failures: failures
    )
  }

  @concurrent nonisolated private static func discoverWindows(
    in applications: [ApplicationCandidate],
    screens: [ScreenSnapshot]
  ) async -> [DiscoveredWindow] {
    await withTaskGroup(of: [DiscoveredWindow].self, returning: [DiscoveredWindow].self) { group in
      for application in applications {
        group.addTask {
          guard !Task.isCancelled else { return [] }
          return discoverWindows(in: application, screens: screens)
        }
      }

      var result: [DiscoveredWindow] = []
      for await windows in group {
        if Task.isCancelled {
          group.cancelAll()
          return []
        }
        result.append(contentsOf: windows)
      }
      return result
    }
  }

  nonisolated private static func discoverWindows(
    in application: ApplicationCandidate,
    screens: [ScreenSnapshot]
  ) -> [DiscoveredWindow] {
    let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(applicationElement, 0.25)

    guard
      let windows: [AXUIElement] = value(
        for: kAXWindowsAttribute as CFString,
        from: applicationElement
      )
    else { return [] }

    let focusedWindow: AXUIElement? = value(
      for: kAXFocusedWindowAttribute as CFString,
      from: applicationElement
    )
    let sortedWindows: [AXUIElement]
    if let focusedWindow {
      sortedWindows = windows.sorted { left, right in
        let leftIsFocused = CFEqual(left, focusedWindow)
        let rightIsFocused = CFEqual(right, focusedWindow)
        return leftIsFocused && !rightIsFocused
      }
    } else {
      sortedWindows = windows
    }

    return sortedWindows.compactMap { window in
      guard !Task.isCancelled else { return nil }
      AXUIElementSetMessagingTimeout(window, 0.25)
      guard
        let frame = frame(of: window),
        isEligible(window, frame: frame, screens: screens)
      else { return nil }

      let title: String = value(for: kAXTitleAttribute as CFString, from: window) ?? ""
      return DiscoveredWindow(
        key: WindowKey(
          processIdentifier: application.processIdentifier,
          accessibilityHash: CFHash(window)
        ),
        processIdentifier: application.processIdentifier,
        applicationName: application.applicationName,
        bundleIdentifier: application.bundleIdentifier,
        title: title,
        frame: frame,
        isFocused: focusedWindow.map { CFEqual(window, $0) } ?? false,
        element: AXElement(window)
      )
    }
  }

  nonisolated private static func isEligible(
    _ window: AXUIElement,
    frame: CGRect,
    screens: [ScreenSnapshot]
  ) -> Bool {
    let role: String? = value(for: kAXRoleAttribute as CFString, from: window)
    guard role == (kAXWindowRole as String) else { return false }

    let subrole: String? = value(for: kAXSubroleAttribute as CFString, from: window)
    if let subrole, subrole != (kAXStandardWindowSubrole as String) { return false }

    let minimized: Bool = value(for: kAXMinimizedAttribute as CFString, from: window) ?? false
    guard !minimized, !isFullScreen(frame, screens: screens) else { return false }

    return isSettable(kAXPositionAttribute as CFString, on: window)
      && isSettable(kAXSizeAttribute as CFString, on: window)
  }

  nonisolated private static func value<T>(
    for attribute: CFString,
    from element: AXUIElement
  ) -> T? {
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success else {
      return nil
    }
    return rawValue as? T
  }

  nonisolated private static func isSettable(
    _ attribute: CFString,
    on element: AXUIElement
  ) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success
      && settable.boolValue
  }

  nonisolated private static func isFullScreen(
    _ windowFrame: CGRect,
    screens: [ScreenSnapshot]
  ) -> Bool {
    screens.contains { screen in
      framesMatch(windowFrame, screen.frame)
    }
  }

  nonisolated private static func frame(of element: AXUIElement) -> CGRect? {
    guard
      let positionValue: AXValue = value(for: kAXPositionAttribute as CFString, from: element),
      let sizeValue: AXValue = value(for: kAXSizeAttribute as CFString, from: element)
    else { return nil }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
      AXValueGetValue(positionValue, .cgPoint, &position),
      AXValueGetValue(sizeValue, .cgSize, &size)
    else { return nil }

    return CGRect(origin: position, size: size)
  }

  @concurrent nonisolated private static func applyFrames(
    _ targets: [WindowFrameTarget<AXElement>]
  ) async -> [WindowFrameOutcome<AXElement>] {
    let transaction = WindowFrameTransaction(accessor: AXWindowFrameAccessor())
    return targets.map { target in
      guard !Task.isCancelled else {
        return WindowFrameOutcome(
          applicationName: target.applicationName,
          handle: target.handle,
          originalFrame: nil,
          failure: "the arrangement was cancelled"
        )
      }
      return transaction.apply([target])[0]
    }
  }

  @concurrent nonisolated private static func restoreFrames(
    _ records: [UndoRecord]
  ) async -> [(UndoRecord, String?)] {
    let transaction = WindowFrameTransaction(accessor: AXWindowFrameAccessor())
    return records.map { record in
      guard !Task.isCancelled else { return (record, "the undo was cancelled") }
      let target = WindowFrameTarget(
        applicationName: record.applicationName,
        handle: record.element,
        destination: record.frame
      )
      return (record, transaction.restore([target])[0].1)
    }
  }

  nonisolated private static func framesMatch(
    _ actual: CGRect,
    _ expected: CGRect,
    tolerance: CGFloat = 2
  ) -> Bool {
    abs(actual.minX - expected.minX) <= tolerance
      && abs(actual.minY - expected.minY) <= tolerance
      && abs(actual.width - expected.width) <= tolerance
      && abs(actual.height - expected.height) <= tolerance
  }

  private func visibleFrame(containing windowFrame: CGRect) -> CGRect? {
    let screens = screenSnapshots()
    guard !screens.isEmpty else { return nil }

    return
      screens
      .map { screen in
        let intersection = screen.frame.intersection(windowFrame)
        let area = intersection.isNull ? 0 : intersection.width * intersection.height
        return (screen.visibleFrame, area)
      }
      .max { $0.1 < $1.1 }?
      .0
  }

  private func screenSnapshots() -> [ScreenSnapshot] {
    NSScreen.screens.map { screen in
      ScreenSnapshot(
        frame: accessibilityFrame(fromAppKitFrame: screen.frame),
        visibleFrame: accessibilityFrame(fromAppKitFrame: screen.visibleFrame)
      )
    }
  }

  private func accessibilityFrame(fromAppKitFrame frame: CGRect) -> CGRect {
    let primaryScreen =
      NSScreen.screens.first(where: { $0.frame.origin == .zero })
      ?? NSScreen.screens[0]
    let primaryTop = primaryScreen.frame.maxY
    return CGRect(
      x: frame.minX,
      y: primaryTop - frame.maxY,
      width: frame.width,
      height: frame.height
    )
  }

  nonisolated private static func description(for error: AXError) -> String {
    switch error {
    case .apiDisabled: "Accessibility access is disabled"
    case .cannotComplete: "the application did not respond"
    case .attributeUnsupported: "the window does not support resizing"
    case .invalidUIElement: "the window is no longer available"
    case .notImplemented: "the application does not implement window resizing"
    default: "window update failed (\(error.rawValue))"
    }
  }
}
