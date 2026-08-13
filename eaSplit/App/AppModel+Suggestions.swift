extension AppModel {
  func applySuggestion(closePanel: Bool = false) {
    guard canApplySuggestion, let suggestion else { return }
    selectedLayout = suggestion.signature.layout
    selectedRatio = suggestion.signature.ratio
    edgeToEdgeWindows = suggestion.signature.spacing.edgeToEdge
    gap = suggestion.signature.spacing.gap
    selectedWindowIDs = suggestion.windowIDs
    applySelection(closePanel: closePanel, source: .suggestion)
  }

  func suppressSuggestion() {
    guard let suggestion else { return }
    historyStore.suppress(suggestion.signature)
    updateSuggestion()
    if let errorMessage = historyStore.errorMessage {
      setStatus(errorMessage, isError: true)
    } else {
      setStatus("This combination will no longer be suggested.", isError: false)
    }
  }

  func resetSuggestions() {
    historyStore.reset()
    updateSuggestion()
    if let errorMessage = historyStore.errorMessage {
      setStatus(errorMessage, isError: true)
    } else {
      setStatus("Learned suggestions reset.", isError: false)
    }
  }

  func recordSuccessfulArrangement(
    _ recipe: SplitRecipe,
    source: ArrangementEvent.Source
  ) {
    guard suggestionsEnabled else { return }
    let signature = ArrangementSignature(recipe: recipe, fallbackSpacing: currentSpacing)
    historyStore.record(
      ArrangementEvent(
        signature: signature,
        performedAt: now(),
        source: source
      )
    )
    updateSuggestion()
  }

  var currentSpacing: ArrangementSpacing {
    ArrangementSpacing(edgeToEdge: edgeToEdgeWindows, gap: gap)
  }

  func updateSuggestion() {
    guard suggestionsEnabled else {
      suggestion = nil
      return
    }

    let suggestionWindows = windows.compactMap { window -> SuggestionWindow? in
      guard let bundleIdentifier = window.bundleIdentifier else { return nil }
      return SuggestionWindow(
        id: window.id,
        bundleIdentifier: bundleIdentifier
      )
    }
    suggestion = suggestionRanker.suggestion(
      in: SplitSuggestionContext(
        recipes: recipeStore.recipes,
        events: historyStore.events,
        suppressedSignatures: historyStore.suppressedSignatures,
        windows: suggestionWindows,
        anchorBundleIdentifier: suggestionWindows.first?.bundleIdentifier,
        fallbackSpacing: currentSpacing,
        now: now()
      )
    )
  }
}
