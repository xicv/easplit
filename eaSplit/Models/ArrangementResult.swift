import Foundation

enum ArrangementOperation {
  case arrange
  case restore

  var completedVerb: String {
    self == .arrange ? "Arranged" : "Restored"
  }

  var failureVerb: String {
    self == .arrange ? "moved" : "restored"
  }
}

struct ArrangementResult: Sendable {
  let arrangedCount: Int
  let failures: [String]
  let warnings: [String]

  init(
    arrangedCount: Int,
    failures: [String],
    warnings: [String] = []
  ) {
    self.arrangedCount = arrangedCount
    self.failures = failures
    self.warnings = warnings
  }

  var succeeded: Bool { failures.isEmpty && arrangedCount > 0 }

  func summary(for operation: ArrangementOperation) -> String {
    if failures.isEmpty {
      let noun = arrangedCount == 1 ? "window" : "windows"
      let completion = "\(operation.completedVerb) \(arrangedCount) \(noun)"
      guard let warning = warnings.first else { return completion }
      if warnings.count == 1 { return "\(completion); \(warning)" }
      return "\(completion); some windows could not be brought forward"
    }

    if arrangedCount == 0 {
      return failures.first ?? "No windows could be arranged"
    }

    return
      "\(operation.completedVerb) \(arrangedCount); "
      + "\(failures.count) could not be \(operation.failureVerb)"
  }
}
