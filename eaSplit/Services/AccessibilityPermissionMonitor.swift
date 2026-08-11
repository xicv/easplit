import Foundation

@MainActor
final class AccessibilityPermissionMonitor {
  private let checkInterval: Duration
  private let maximumChecks: Int
  private var monitoringTask: Task<Void, Never>?

  init(
    checkInterval: Duration = .milliseconds(500),
    maximumChecks: Int = 240
  ) {
    self.checkInterval = checkInterval
    self.maximumChecks = maximumChecks
  }

  func start(
    check: @escaping @MainActor () -> Bool,
    onGranted: @escaping @MainActor () -> Void,
    onTimeout: @escaping @MainActor () -> Void
  ) {
    stop()

    if check() {
      onGranted()
      return
    }

    let checkInterval = self.checkInterval
    let maximumChecks = self.maximumChecks
    monitoringTask = Task { @MainActor [weak self] in
      for _ in 0..<maximumChecks {
        do {
          try await Task.sleep(for: checkInterval)
        } catch {
          return
        }

        guard self != nil, !Task.isCancelled else { return }
        if check() {
          self?.monitoringTask = nil
          onGranted()
          return
        }
      }

      guard self != nil, !Task.isCancelled else { return }
      self?.monitoringTask = nil
      onTimeout()
    }
  }

  func stop() {
    monitoringTask?.cancel()
    monitoringTask = nil
  }
}
