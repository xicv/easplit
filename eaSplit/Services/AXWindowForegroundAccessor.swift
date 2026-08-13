import AppKit
import ApplicationServices

final class AXElement: @unchecked Sendable {
  let value: AXUIElement

  init(_ value: AXUIElement) {
    self.value = value
  }
}

struct AXWindowForegroundAccessor: WindowForegroundAccessing {
  func activateApplication(owning handle: AXElement) -> String? {
    var processIdentifier: pid_t = 0
    let processResult = AXUIElementGetPid(handle.value, &processIdentifier)
    guard processResult == .success else {
      return "the owning application could not be identified"
    }
    guard
      let application = NSRunningApplication(processIdentifier: processIdentifier),
      !application.isTerminated
    else {
      return "the owning application is no longer running"
    }
    guard application.activate(options: []) else {
      return "the owning application could not be brought forward"
    }
    for _ in 0..<25 {
      if application.isActive { return nil }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return "the owning application did not become active"
  }

  func raise(_ handle: AXElement) -> String? {
    AXUIElementSetMessagingTimeout(handle.value, 0.5)
    let result = AXUIElementPerformAction(
      handle.value,
      kAXRaiseAction as CFString
    )
    return result == .success
      ? nil
      : Self.description(for: result, action: "brought forward")
  }

  func focus(_ handle: AXElement) -> String? {
    AXUIElementSetMessagingTimeout(handle.value, 0.5)
    let result = AXUIElementSetAttributeValue(
      handle.value,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    return result == .success
      ? nil
      : Self.description(for: result, action: "given keyboard focus")
  }

  private static func description(for error: AXError, action: String) -> String {
    switch error {
    case .actionUnsupported, .attributeUnsupported:
      "the window could not be \(action)"
    case .cannotComplete:
      "the application did not respond while the window was being \(action)"
    case .invalidUIElement:
      "the window closed before it could be \(action)"
    case .notImplemented:
      "the application does not support having its window \(action)"
    default:
      "the window could not be \(action) (\(error.rawValue))"
    }
  }
}
