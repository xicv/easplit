import Foundation

struct ArrangementSpacing: Codable, Equatable, Hashable, Sendable {
  let edgeToEdge: Bool
  let gap: Double

  init(edgeToEdge: Bool, gap: Double) {
    self.edgeToEdge = edgeToEdge
    self.gap = min(max(gap, 0), 32)
  }

}

struct ArrangementApplication: Codable, Hashable, Sendable {
  let bundleIdentifier: String
  let applicationName: String

  static func == (left: Self, right: Self) -> Bool {
    left.bundleIdentifier == right.bundleIdentifier
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundleIdentifier)
  }
}

struct ArrangementSignature: Codable, Equatable, Hashable, Sendable {
  let applications: [ArrangementApplication]
  let layout: SplitLayout
  let ratio: SplitRatio
  let spacing: ArrangementSpacing

  init(recipe: SplitRecipe, fallbackSpacing: ArrangementSpacing) {
    applications = recipe.slots.map {
      ArrangementApplication(
        bundleIdentifier: $0.bundleIdentifier,
        applicationName: $0.applicationName
      )
    }
    layout = recipe.layout
    ratio = recipe.ratio
    spacing = recipe.spacing ?? fallbackSpacing
  }
}

struct ArrangementEvent: Codable, Equatable, Sendable {
  enum Source: String, Codable, Sendable {
    case manual
    case quickSplit
    case repeatLast
    case savedRecipe
    case suggestion
  }

  let id: UUID
  let signature: ArrangementSignature
  let performedAt: Date
  let source: Source

  init(
    id: UUID = UUID(),
    signature: ArrangementSignature,
    performedAt: Date,
    source: Source
  ) {
    self.id = id
    self.signature = signature
    self.performedAt = performedAt
    self.source = source
  }
}

struct SuggestionWindow: Equatable, Sendable {
  let id: UUID
  let bundleIdentifier: String
}

struct SplitSuggestion: Equatable, Sendable {
  enum Reason: Equatable, Sendable {
    case saved(name: String)
    case frequentlyUsed(count: Int)
  }

  let signature: ArrangementSignature
  let windowIDs: [UUID]
  let reason: Reason
}

struct SplitSuggestionContext: Sendable {
  let recipes: [SplitRecipe]
  let events: [ArrangementEvent]
  let suppressedSignatures: Set<ArrangementSignature>
  let windows: [SuggestionWindow]
  let anchorBundleIdentifier: String?
  let fallbackSpacing: ArrangementSpacing
  let now: Date
}
