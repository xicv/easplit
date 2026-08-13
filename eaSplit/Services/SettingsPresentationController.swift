import AppKit

@MainActor
struct SettingsPresentationController {
  private let activateApplication: @MainActor () -> Void

  init(
    activateApplication: @escaping @MainActor () -> Void = {
      NSApp.activate()
    }
  ) {
    self.activateApplication = activateApplication
  }

  func presentSettings(openSettings: @MainActor () -> Void) {
    activateApplication()
    openSettings()
  }
}
