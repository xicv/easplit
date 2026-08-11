import OSLog

enum AppLogger {
  static let arrangement = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.xicao.easplit",
    category: "window-arrangement"
  )
}

