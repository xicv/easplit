import AppKit

@MainActor
private final class AcceptanceFixtureDelegate: NSObject, NSApplicationDelegate {
  private var windows: [NSWindow] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    windows = [
      makeWindow(
        title: "Browser Fixture",
        frame: NSRect(x: 120, y: 180, width: 760, height: 560),
        minimumSize: NSSize(width: 500, height: 320)
      ),
      makeWindow(
        title: "Chat Fixture",
        frame: NSRect(x: 920, y: 220, width: 560, height: 640),
        minimumSize: NSSize(width: 360, height: 420)
      ),
      makeFixedWindow(
        title: "Fixed Panel — should not appear",
        frame: NSRect(x: 420, y: 80, width: 360, height: 180)
      ),
    ]

    windows.forEach { $0.orderFrontRegardless() }
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func makeWindow(
    title: String,
    frame: NSRect,
    minimumSize: NSSize
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.minSize = minimumSize
    window.contentView = label(title)
    return window
  }

  private func makeFixedWindow(title: String, frame: NSRect) -> NSWindow {
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.contentView = label(title)
    return window
  }

  private func label(_ text: String) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.alignment = .center
    label.font = .preferredFont(forTextStyle: .title2)
    let container = NSView()
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    return container
  }
}

let application = NSApplication.shared
private let delegate = AcceptanceFixtureDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
