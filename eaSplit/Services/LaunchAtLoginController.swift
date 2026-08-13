import Observation
import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
  func openSystemSettingsLoginItems()
}

@MainActor
private final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
  var status: SMAppService.Status { SMAppService.mainApp.status }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }

  func openSystemSettingsLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

@MainActor
@Observable
final class LaunchAtLoginController {
  private(set) var status: SMAppService.Status = .notRegistered
  private(set) var errorMessage: String?
  private(set) var hasLoadedStatus = false

  private let service: any LaunchAtLoginServicing

  init(service: any LaunchAtLoginServicing = SystemLaunchAtLoginService()) {
    self.service = service
  }

  var isEnabled: Bool {
    status == .enabled || status == .requiresApproval
  }

  var requiresApproval: Bool {
    status == .requiresApproval
  }

  var statusDescription: String {
    guard hasLoadedStatus else { return "Checking…" }

    return switch status {
    case .notRegistered: "Off"
    case .enabled: "On"
    case .requiresApproval: "Needs approval"
    case .notFound: "Unavailable"
    @unknown default: "Unknown"
    }
  }

  func refresh() {
    status = service.status
    hasLoadedStatus = true
  }

  func setEnabled(_ enabled: Bool) {
    errorMessage = nil
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
  }

  func openSystemSettings() {
    service.openSystemSettingsLoginItems()
  }
}
