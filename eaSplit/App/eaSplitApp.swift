import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model: AppModel
  private let presentationController: AppPresentationController
  private let hotKeyService: HotKeyService

  override init() {
    let model = AppModel()
    self.model = model
    presentationController = AppPresentationController {
      model.showPicker()
    }
    hotKeyService = HotKeyService(
      onOpenPicker: { [weak model] in model?.showPicker() },
      onQuickSplit: { [weak model] in model?.quickSplit() },
      onRepeatLastSplit: { [weak model] in model?.repeatLastSplit() }
    )
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    presentationController.presentInitialPickerIfNeeded()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    presentationController.presentPickerForReopen()
    return false
  }
}

@main
struct eaSplitApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("eaSplit", systemImage: "rectangle.split.2x1") {
      SplitPickerView(model: appDelegate.model, presentation: .menuBar)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(model: appDelegate.model)
    }
  }
}
