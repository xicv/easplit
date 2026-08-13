import ServiceManagement
import Testing
@testable import eaSplit

@Suite
@MainActor
struct LaunchAtLoginControllerTests {
  @Test
  func systemStatusIsLoadedOnlyWhenSettingsRequestIt() {
    let service = LaunchAtLoginServiceSpy(status: .enabled)
    let controller = LaunchAtLoginController(service: service)

    #expect(service.statusRequestCount == 0)
    #expect(controller.statusDescription == "Checking…")

    controller.refresh()

    #expect(service.statusRequestCount == 1)
    #expect(controller.statusDescription == "On")
  }

  @Test
  func enablingRegistersAndRefreshesStatus() {
    let service = LaunchAtLoginServiceSpy(status: .enabled)
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(true)

    #expect(service.registerCallCount == 1)
    #expect(service.unregisterCallCount == 0)
    #expect(service.statusRequestCount == 1)
    #expect(controller.isEnabled)
    #expect(controller.errorMessage == nil)
  }

  @Test
  func disablingUnregistersAndRefreshesStatus() {
    let service = LaunchAtLoginServiceSpy(status: .notRegistered)
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(false)

    #expect(service.registerCallCount == 0)
    #expect(service.unregisterCallCount == 1)
    #expect(service.statusRequestCount == 1)
    #expect(!controller.isEnabled)
  }

  @Test
  func registrationFailureIsPresentedAndStatusStillRefreshes() {
    let service = LaunchAtLoginServiceSpy(
      status: .notRegistered,
      registrationError: LaunchAtLoginTestError.registrationFailed
    )
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(true)

    #expect(service.registerCallCount == 1)
    #expect(service.statusRequestCount == 1)
    #expect(controller.errorMessage == "The login item could not be enabled.")
    #expect(!controller.isEnabled)
  }

  @Test
  func systemSettingsActionIsDelegated() {
    let service = LaunchAtLoginServiceSpy(status: .notRegistered)
    let controller = LaunchAtLoginController(service: service)

    controller.openSystemSettings()

    #expect(service.openSystemSettingsCallCount == 1)
  }
}

@MainActor
private final class LaunchAtLoginServiceSpy: LaunchAtLoginServicing {
  private let stubbedStatus: SMAppService.Status
  private let registrationError: (any Error)?
  private(set) var statusRequestCount = 0
  private(set) var registerCallCount = 0
  private(set) var unregisterCallCount = 0
  private(set) var openSystemSettingsCallCount = 0

  init(status: SMAppService.Status, registrationError: (any Error)? = nil) {
    stubbedStatus = status
    self.registrationError = registrationError
  }

  var status: SMAppService.Status {
    statusRequestCount += 1
    return stubbedStatus
  }

  func register() throws {
    registerCallCount += 1
    if let registrationError { throw registrationError }
  }
  func unregister() throws { unregisterCallCount += 1 }
  func openSystemSettingsLoginItems() { openSystemSettingsCallCount += 1 }
}

private enum LaunchAtLoginTestError: LocalizedError {
  case registrationFailed

  var errorDescription: String? { "The login item could not be enabled." }
}
