import OSLog

enum AppLogger {
  static let arrangement = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.xicao.easplit",
    category: "window-arrangement"
  )

  static let performance = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.xicao.easplit",
    category: "performance"
  )
}
