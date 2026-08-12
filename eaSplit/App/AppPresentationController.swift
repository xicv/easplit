import Foundation

@MainActor
final class AppPresentationController {
  private enum DefaultsKey {
    static let hasShownInitialPicker = "hasShownInitialPicker"
  }

  private let defaults: UserDefaults
  private let showPicker: @MainActor () -> Void

  init(
    defaults: UserDefaults = .standard,
    showPicker: @escaping @MainActor () -> Void
  ) {
    self.defaults = defaults
    self.showPicker = showPicker
  }

  func presentInitialPickerIfNeeded() {
    guard !defaults.bool(forKey: DefaultsKey.hasShownInitialPicker) else { return }

    defaults.set(true, forKey: DefaultsKey.hasShownInitialPicker)
    showPicker()
  }

  func presentPickerForReopen() {
    showPicker()
  }
}
