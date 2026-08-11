import AppKit

struct WindowDescriptor: Identifiable {
  let id: UUID
  let processIdentifier: pid_t
  let applicationName: String
  let bundleIdentifier: String?
  let title: String
  let icon: NSImage
  let frame: CGRect
  let isFocused: Bool

  var displayTitle: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? applicationName : trimmed
  }
}

