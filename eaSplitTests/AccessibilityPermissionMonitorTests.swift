import XCTest
@testable import eaSplit

@MainActor
private final class PermissionState {
  var isTrusted = false
}

@MainActor
final class AccessibilityPermissionMonitorTests: XCTestCase {
  func testReportsPermissionGrantedAfterAsynchronousStateChange() async {
    let state = PermissionState()
    let granted = expectation(description: "Permission grant observed")
    let monitor = AccessibilityPermissionMonitor(
      checkInterval: .milliseconds(5),
      maximumChecks: 20
    )

    monitor.start(
      check: { state.isTrusted },
      onGranted: { granted.fulfill() },
      onTimeout: { XCTFail("Monitor timed out before observing permission") }
    )

    state.isTrusted = true

    await fulfillment(of: [granted], timeout: 1)
  }

  func testReportsTimeoutWhenPermissionRemainsDenied() async {
    let timedOut = expectation(description: "Permission monitoring timed out")
    let monitor = AccessibilityPermissionMonitor(
      checkInterval: .milliseconds(5),
      maximumChecks: 2
    )

    monitor.start(
      check: { false },
      onGranted: { XCTFail("Permission should remain denied") },
      onTimeout: { timedOut.fulfill() }
    )

    await fulfillment(of: [timedOut], timeout: 1)
  }
}
