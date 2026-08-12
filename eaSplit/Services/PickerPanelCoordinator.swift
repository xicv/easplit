import AppKit
import SwiftUI

@MainActor
final class PickerPanelCoordinator: PickerPresenting {
  private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
  }

  private var panel: NSPanel?

  func show(model: AppModel) {
    let panel = panel ?? makePanel()
    let rootView = SplitPickerView(model: model, presentation: .panel)
      .frame(width: 420, height: 560)
    panel.contentView = NSHostingView(rootView: rootView)
    position(panel)

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
  }

  func dismiss() {
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    return panel
  }

  private func position(_ panel: NSPanel) {
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else {
      panel.center()
      return
    }

    let origin = NSPoint(
      x: visibleFrame.midX - (panel.frame.width / 2),
      y: visibleFrame.midY - (panel.frame.height / 2)
    )
    panel.setFrameOrigin(origin)
  }
}
