import AppKit

@MainActor
final class RecentApplicationTracker {
  private(set) var processIdentifiers: [pid_t] = []
  private var observer: NSObjectProtocol?

  init() {
    if let frontmost = NSWorkspace.shared.frontmostApplication {
      record(frontmost)
    }

    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
      else { return }

      MainActor.assumeIsolated {
        self?.record(application)
      }
    }
  }

  private func record(_ application: NSRunningApplication) {
    guard
      application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      application.activationPolicy == .regular
    else { return }

    processIdentifiers.removeAll { $0 == application.processIdentifier }
    processIdentifiers.insert(application.processIdentifier, at: 0)
    processIdentifiers = Array(processIdentifiers.prefix(20))
  }
}

