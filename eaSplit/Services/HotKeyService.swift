import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let openPicker = Self("openPicker")
  static let quickSplit = Self("quickSplit")
  static let repeatLastSplit = Self("repeatLastSplit")
}

@MainActor
final class HotKeyService {
  init(
    onOpenPicker: @escaping @MainActor () -> Void,
    onQuickSplit: @escaping @MainActor () -> Void,
    onRepeatLastSplit: @escaping @MainActor () -> Void
  ) {
    KeyboardShortcuts.onKeyUp(for: .openPicker) {
      Task { @MainActor in onOpenPicker() }
    }
    KeyboardShortcuts.onKeyUp(for: .quickSplit) {
      Task { @MainActor in onQuickSplit() }
    }
    KeyboardShortcuts.onKeyUp(for: .repeatLastSplit) {
      Task { @MainActor in onRepeatLastSplit() }
    }
  }
}

