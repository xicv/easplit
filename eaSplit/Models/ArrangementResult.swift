import Foundation

struct ArrangementResult: Sendable {
  let arrangedCount: Int
  let failures: [String]

  var succeeded: Bool { failures.isEmpty && arrangedCount > 0 }

  var summary: String {
    if failures.isEmpty {
      return arrangedCount == 1 ? "Arranged 1 window" : "Arranged \(arrangedCount) windows"
    }

    if arrangedCount == 0 {
      return failures.first ?? "No windows could be arranged"
    }

    return "Arranged \(arrangedCount); \(failures.count) could not be moved"
  }
}

