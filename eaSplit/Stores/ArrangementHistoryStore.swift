import Foundation

@MainActor
protocol ArrangementHistoryStoring: AnyObject {
  var events: [ArrangementEvent] { get }
  var suppressedSignatures: Set<ArrangementSignature> { get }
  var errorMessage: String? { get }

  func record(_ event: ArrangementEvent)
  func suppress(_ signature: ArrangementSignature)
  func reset()
}

@MainActor
final class ArrangementHistoryStore: ArrangementHistoryStoring {
  private(set) var events: [ArrangementEvent] = []
  private(set) var suppressedSignatures: Set<ArrangementSignature> = []
  private(set) var errorMessage: String?

  private let fileURL: URL
  private let fileManager: FileManager
  private let now: () -> Date

  init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default,
    now: @escaping () -> Date = Date.init
  ) {
    self.fileManager = fileManager
    self.now = now

    if let fileURL {
      self.fileURL = fileURL
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      self.fileURL = applicationSupport
        .appendingPathComponent("eaSplit", isDirectory: true)
        .appendingPathComponent("arrangement-history.json", isDirectory: false)
    }

    load()
  }

  func record(_ event: ArrangementEvent) {
    let previousEvents = events
    let cutoff = now().addingTimeInterval(-90 * 24 * 60 * 60)
    events = Array(
      (events + [event])
        .filter { $0.performedAt >= cutoff }
        .sorted { $0.performedAt < $1.performedAt }
        .suffix(100)
    )
    if !persist() {
      events = previousEvents
    }
  }

  func suppress(_ signature: ArrangementSignature) {
    let previousSignatures = suppressedSignatures
    suppressedSignatures.insert(signature)
    if !persist() {
      suppressedSignatures = previousSignatures
    }
  }

  func reset() {
    let previousEvents = events
    let previousSignatures = suppressedSignatures
    events = []
    suppressedSignatures = []
    if !persist() {
      events = previousEvents
      suppressedSignatures = previousSignatures
    }
  }

  private struct Document: Codable {
    let version: Int
    var events: [ArrangementEvent]
    var suppressedSignatures: [ArrangementSignature]
  }

  private func load() {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }

    do {
      let data = try Data(contentsOf: fileURL)
      let document = try JSONDecoder().decode(Document.self, from: data)
      guard document.version == 1 else {
        errorMessage = "Split suggestions use an unsupported data version."
        return
      }
      events = document.events
      suppressedSignatures = Set(document.suppressedSignatures)
      errorMessage = nil
    } catch {
      errorMessage = "Split suggestions could not be read: \(error.localizedDescription)"
    }
  }

  @discardableResult
  private func persist() -> Bool {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let document = Document(
        version: 1,
        events: events,
        suppressedSignatures: Array(suppressedSignatures)
      )
      let data = try JSONEncoder().encode(document)
      try data.write(to: fileURL, options: .atomic)
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Split suggestions could not be written: \(error.localizedDescription)"
      return false
    }
  }
}
