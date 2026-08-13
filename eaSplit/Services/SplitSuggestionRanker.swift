import Foundation

struct SplitSuggestionRanker {
  func suggestion(in context: SplitSuggestionContext) -> SplitSuggestion? {
    let orderedRecipes = context.recipes.enumerated().sorted { left, right in
      let leftContainsAnchor = containsAnchor(left.element, context.anchorBundleIdentifier)
      let rightContainsAnchor = containsAnchor(right.element, context.anchorBundleIdentifier)
      if leftContainsAnchor != rightContainsAnchor { return leftContainsAnchor }
      return left.offset < right.offset
    }

    for (_, recipe) in orderedRecipes {
      let signature = ArrangementSignature(
        recipe: recipe,
        fallbackSpacing: context.fallbackSpacing
      )
      guard !context.suppressedSignatures.contains(signature) else { continue }
      guard let windowIDs = resolvedWindowIDs(for: signature, windows: context.windows) else {
        continue
      }

      return SplitSuggestion(
        signature: signature,
        windowIDs: windowIDs,
        reason: .saved(name: recipe.name)
      )
    }

    let cutoff = context.now.addingTimeInterval(-30 * 24 * 60 * 60)
    let groupedEvents = Dictionary(grouping: context.events.filter {
      $0.performedAt >= cutoff && $0.performedAt <= context.now
    }, by: \.signature)

    let candidates = groupedEvents.compactMap { signature, matchingEvents -> LearnedCandidate? in
      guard matchingEvents.count >= 2 else { return nil }
      guard !context.suppressedSignatures.contains(signature) else { return nil }
      if let anchorBundleIdentifier = context.anchorBundleIdentifier,
        !signature.applications.contains(where: {
          $0.bundleIdentifier == anchorBundleIdentifier
        })
      {
        return nil
      }
      guard let windowIDs = resolvedWindowIDs(for: signature, windows: context.windows) else {
        return nil
      }

      return LearnedCandidate(
        suggestion: SplitSuggestion(
          signature: signature,
          windowIDs: windowIDs,
          reason: .frequentlyUsed(count: matchingEvents.count)
        ),
        count: matchingEvents.count,
        lastUsedAt: matchingEvents.map(\.performedAt).max() ?? .distantPast
      )
    }
    .sorted {
      if $0.count != $1.count { return $0.count > $1.count }
      return $0.lastUsedAt > $1.lastUsedAt
    }

    return candidates.first?.suggestion
  }

  private struct LearnedCandidate {
    let suggestion: SplitSuggestion
    let count: Int
    let lastUsedAt: Date
  }

  private func containsAnchor(_ recipe: SplitRecipe, _ anchorBundleIdentifier: String?) -> Bool {
    guard let anchorBundleIdentifier else { return false }
    return recipe.slots.contains { $0.bundleIdentifier == anchorBundleIdentifier }
  }

  private func resolvedWindowIDs(
    for signature: ArrangementSignature,
    windows: [SuggestionWindow]
  ) -> [UUID]? {
    var usedWindowIDs = Set<UUID>()
    var result: [UUID] = []

    for application in signature.applications {
      guard
        let window = windows.first(where: {
          $0.bundleIdentifier == application.bundleIdentifier && !usedWindowIDs.contains($0.id)
        })
      else { return nil }

      usedWindowIDs.insert(window.id)
      result.append(window.id)
    }

    return result
  }
}
