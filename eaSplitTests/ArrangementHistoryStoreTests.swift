import Foundation
import XCTest
@testable import eaSplit

@MainActor
final class ArrangementHistoryStoreTests: XCTestCase {
  func testSuccessfulArrangementPersistsAndReloads() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("arrangement-history.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let event = makeEvent(performedAt: Date(timeIntervalSince1970: 1_000))

    let store = ArrangementHistoryStore(
      fileURL: fileURL,
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    store.record(event)

    let reloaded = ArrangementHistoryStore(
      fileURL: fileURL,
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    XCTAssertNil(reloaded.errorMessage)
    XCTAssertEqual(reloaded.events, [event])
  }

  func testHistoryKeepsOnlyOneHundredRecentEvents() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("arrangement-history.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ArrangementHistoryStore(fileURL: fileURL, now: { now })

    store.record(makeEvent(performedAt: now.addingTimeInterval(-91 * 24 * 60 * 60)))
    for offset in 0...100 {
      store.record(makeEvent(performedAt: now.addingTimeInterval(Double(offset))))
    }

    XCTAssertEqual(store.events.count, 100)
    XCTAssertEqual(store.events.first?.performedAt, now.addingTimeInterval(1))
    XCTAssertEqual(store.events.last?.performedAt, now.addingTimeInterval(100))
  }

  func testSuppressionPersistsAndResetClearsSuggestionData() {
    let now = Date(timeIntervalSince1970: 2_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("arrangement-history.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let event = makeEvent(performedAt: now)
    let store = ArrangementHistoryStore(fileURL: fileURL, now: { now })

    store.record(event)
    store.suppress(event.signature)

    let reloaded = ArrangementHistoryStore(fileURL: fileURL, now: { now })
    XCTAssertEqual(reloaded.events, [event])
    XCTAssertEqual(reloaded.suppressedSignatures, Set([event.signature]))

    reloaded.reset()
    let resetStore = ArrangementHistoryStore(fileURL: fileURL, now: { now })
    XCTAssertTrue(resetStore.events.isEmpty)
    XCTAssertTrue(resetStore.suppressedSignatures.isEmpty)
  }

  func testPersistedHistoryContainsNoWindowTitles() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("arrangement-history.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let event = makeEvent(performedAt: Date(timeIntervalSince1970: 1_000))

    ArrangementHistoryStore(fileURL: fileURL).record(event)

    let persistedText = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertFalse(persistedText.localizedCaseInsensitiveContains("windowTitle"))
    XCTAssertFalse(persistedText.contains("Browser"))
  }

  private func makeEvent(performedAt: Date) -> ArrangementEvent {
    ArrangementEvent(
      signature: ArrangementSignature(
        recipe: SplitRecipe(
          name: "Last Split",
          layout: .twoColumns,
          ratio: .equal,
          slots: [
            .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
            .init(bundleIdentifier: "com.apple.Notes", applicationName: "Notes"),
          ]
        ),
        fallbackSpacing: .init(edgeToEdge: false, gap: 8)
      ),
      performedAt: performedAt,
      source: .manual
    )
  }
}
