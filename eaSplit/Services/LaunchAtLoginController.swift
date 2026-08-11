import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
  private(set) var status = SMAppService.mainApp.status
  private(set) var errorMessage: String?

  var isEnabled: Bool {
    status == .enabled || status == .requiresApproval
  }

  var requiresApproval: Bool {
    status == .requiresApproval
  }

  var statusDescription: String {
    switch status {
    case .notRegistered: "Off"
    case .enabled: "On"
    case .requiresApproval: "Needs approval"
    case .notFound: "Unavailable"
    @unknown default: "Unknown"
    }
  }

  func refresh() {
    status = SMAppService.mainApp.status
  }

  func setEnabled(_ enabled: Bool) {
    errorMessage = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
