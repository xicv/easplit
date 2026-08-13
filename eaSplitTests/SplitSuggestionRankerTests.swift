import Foundation
import Testing
@testable import eaSplit

struct SplitSuggestionRankerTests {
  @Test
  func availableSavedRecipeBecomesSuggestion() throws {
    let safariID = UUID()
    let notesID = UUID()
    let recipe = SplitRecipe(
      name: "Research",
      layout: .twoColumns,
      ratio: .equal,
      slots: [
        .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
        .init(bundleIdentifier: "com.apple.Notes", applicationName: "Notes"),
      ]
    )

    let suggestion = SplitSuggestionRanker().suggestion(
      in: SplitSuggestionContext(
        recipes: [recipe],
        events: [],
        suppressedSignatures: [],
        windows: [
          .init(id: safariID, bundleIdentifier: "com.apple.Safari"),
          .init(id: notesID, bundleIdentifier: "com.apple.Notes"),
        ],
        anchorBundleIdentifier: "com.apple.Safari",
        fallbackSpacing: .init(edgeToEdge: false, gap: 8),
        now: Date(timeIntervalSince1970: 1_000)
      )
    )

    let unwrapped = try #require(suggestion)
    #expect(unwrapped.windowIDs == [safariID, notesID])
    #expect(unwrapped.reason == .saved(name: "Research"))
  }

  @Test
  func repeatedRecentArrangementBecomesSuggestion() throws {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let signature = makeSignature()
    let windows = makeWindows()
    let events = [
      ArrangementEvent(
        signature: signature,
        performedAt: now.addingTimeInterval(-600),
        source: .manual
      ),
      ArrangementEvent(
        signature: signature,
        performedAt: now.addingTimeInterval(-60),
        source: .manual
      ),
    ]

    let suggestion = SplitSuggestionRanker().suggestion(
      in: SplitSuggestionContext(
        recipes: [],
        events: events,
        suppressedSignatures: [],
        windows: windows,
        anchorBundleIdentifier: "com.apple.Safari",
        fallbackSpacing: .init(edgeToEdge: false, gap: 8),
        now: now
      )
    )

    let unwrapped = try #require(suggestion)
    #expect(unwrapped.windowIDs == windows.map(\.id))
    #expect(unwrapped.reason == .frequentlyUsed(count: 2))
  }

  @Test
  func savedRecipeOutranksLearnedHistoryAndKeepsItsSpacing() throws {
    let now = Date(timeIntervalSince1970: 3_000_000)
    let learnedSignature = makeSignature()
    let saved = SplitRecipe(
      name: "Edge to Edge",
      layout: .twoRows,
      ratio: .leading,
      slots: [
        .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
        .init(bundleIdentifier: "com.apple.Notes", applicationName: "Notes"),
      ],
      spacing: .init(edgeToEdge: true, gap: 20)
    )

    let suggestion = SplitSuggestionRanker().suggestion(
      in: SplitSuggestionContext(
        recipes: [saved],
        events: [
          .init(signature: learnedSignature, performedAt: now, source: .manual),
          .init(signature: learnedSignature, performedAt: now, source: .manual),
        ],
        suppressedSignatures: [],
        windows: makeWindows(),
        anchorBundleIdentifier: "com.apple.Safari",
        fallbackSpacing: .init(edgeToEdge: false, gap: 8),
        now: now
      )
    )

    #expect(suggestion?.reason == .saved(name: "Edge to Edge"))
    #expect(suggestion?.signature.spacing == .init(edgeToEdge: true, gap: 20))
  }

  @Test
  func oneUseStaleUnavailableAndSuppressedCandidatesAreNotSuggested() {
    let now = Date(timeIntervalSince1970: 4_000_000)
    let signature = makeSignature()
    let oneUse = ArrangementEvent(signature: signature, performedAt: now, source: .manual)

    let ranker = SplitSuggestionRanker()
    #expect(
      ranker.suggestion(
        in: SplitSuggestionContext(
          recipes: [],
          events: [oneUse],
          suppressedSignatures: [],
          windows: makeWindows(),
          anchorBundleIdentifier: "com.apple.Safari",
          fallbackSpacing: .init(edgeToEdge: false, gap: 8),
          now: now
        )
      ) == nil
    )

    let stale = ArrangementEvent(
      signature: signature,
      performedAt: now.addingTimeInterval(-31 * 24 * 60 * 60),
      source: .manual
    )
    #expect(
      ranker.suggestion(
        in: SplitSuggestionContext(
          recipes: [],
          events: [stale, stale],
          suppressedSignatures: [],
          windows: makeWindows(),
          anchorBundleIdentifier: "com.apple.Safari",
          fallbackSpacing: .init(edgeToEdge: false, gap: 8),
          now: now
        )
      ) == nil
    )

    #expect(
      ranker.suggestion(
        in: SplitSuggestionContext(
          recipes: [],
          events: [oneUse, oneUse],
          suppressedSignatures: [],
          windows: Array(makeWindows().prefix(1)),
          anchorBundleIdentifier: "com.apple.Safari",
          fallbackSpacing: .init(edgeToEdge: false, gap: 8),
          now: now
        )
      ) == nil
    )

    #expect(
      ranker.suggestion(
        in: SplitSuggestionContext(
          recipes: [],
          events: [oneUse, oneUse],
          suppressedSignatures: [signature],
          windows: makeWindows(),
          anchorBundleIdentifier: "com.apple.Safari",
          fallbackSpacing: .init(edgeToEdge: false, gap: 8),
          now: now
        )
      ) == nil
    )
  }

  private func makeSignature() -> ArrangementSignature {
    ArrangementSignature(
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
    )
  }

  private func makeWindows() -> [SuggestionWindow] {
    [
      .init(id: UUID(), bundleIdentifier: "com.apple.Safari"),
      .init(id: UUID(), bundleIdentifier: "com.apple.Notes"),
    ]
  }
}
