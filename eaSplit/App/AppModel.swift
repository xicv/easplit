import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
  private enum DefaultsKey {
    static let selectedLayout = "selectedLayout"
    static let selectedRatio = "selectedRatio"
    static let gap = "windowGap"
    static let edgeToEdgeWindows = "edgeToEdgeWindows"
    static let bringArrangedWindowsForward = "bringArrangedWindowsForward"
    static let hideOtherApplicationsAfterSplit = "hideOtherApplicationsAfterSplit"
    static let lastArrangement = "lastArrangement"
    static let suggestionsEnabled = "suggestionsEnabled"
  }

  private let accessibilityClient: any WindowControlling
  private let applicationVisibilityController: any ApplicationVisibilityControlling
  private let permissionMonitor: AccessibilityPermissionMonitor
  private let recentApplicationTracker: RecentApplicationTracker
  let historyStore: any ArrangementHistoryStoring
  let suggestionRanker: SplitSuggestionRanker
  private let pickerPanelCoordinator: any PickerPresenting
  private let defaults: UserDefaults
  let now: () -> Date
  private var lastArrangement: SplitRecipe?
  private var refreshTask: Task<Void, Never>?
  private var refreshRequested = false
  private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
  private var preparationTask: Task<Void, Never>?

  let recipeStore: RecipeStore
  let launchAtLogin: LaunchAtLoginController

  var windows: [WindowDescriptor] = []
  var selectedWindowIDs: [UUID] = []
  var permissionGranted = false
  var isAwaitingPermission = false
  var isRefreshing = false
  var isArranging = false
  var canUndo = false
  var statusMessage: String?
  var statusIsError = false
  var suggestion: SplitSuggestion?

  var selectedLayout: SplitLayout {
    didSet {
      defaults.set(selectedLayout.rawValue, forKey: DefaultsKey.selectedLayout)
      reconcileSelection()
    }
  }

  var selectedRatio: SplitRatio {
    didSet {
      defaults.set(selectedRatio.rawValue, forKey: DefaultsKey.selectedRatio)
    }
  }

  var gap: Double {
    didSet {
      let clamped = min(max(gap, 0), 32)
      if clamped != gap {
        gap = clamped
        return
      }
      defaults.set(gap, forKey: DefaultsKey.gap)
    }
  }

  var edgeToEdgeWindows: Bool {
    didSet {
      defaults.set(edgeToEdgeWindows, forKey: DefaultsKey.edgeToEdgeWindows)
    }
  }

  var bringArrangedWindowsForward: Bool {
    didSet {
      defaults.set(
        bringArrangedWindowsForward,
        forKey: DefaultsKey.bringArrangedWindowsForward
      )
    }
  }

  var hideOtherApplicationsAfterSplit: Bool {
    didSet {
      defaults.set(
        hideOtherApplicationsAfterSplit,
        forKey: DefaultsKey.hideOtherApplicationsAfterSplit
      )
    }
  }

  var suggestionsEnabled: Bool {
    didSet {
      defaults.set(suggestionsEnabled, forKey: DefaultsKey.suggestionsEnabled)
      updateSuggestion()
    }
  }

  var canApplySelection: Bool {
    permissionGranted
      && !isArranging
      && !isRefreshing
      && selectedWindowIDs.count == selectedLayout.slotCount
  }

  var canRepeatLastSplit: Bool {
    lastArrangement != nil && !isArranging && !isRefreshing
  }

  var canApplySuggestion: Bool {
    suggestion != nil && permissionGranted && !isArranging && !isRefreshing
  }

  var suggestedWindows: [WindowDescriptor] {
    guard let suggestion else { return [] }
    return suggestion.windowIDs.compactMap { id in
      windows.first { $0.id == id }
    }
  }

  var applicationDisplayName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "eaSplit"
  }

  init(
    accessibilityClient: any WindowControlling = AccessibilityWindowClient(),
    applicationVisibilityController: any ApplicationVisibilityControlling =
      ApplicationVisibilityController(),
    permissionMonitor: AccessibilityPermissionMonitor = AccessibilityPermissionMonitor(),
    recentApplicationTracker: RecentApplicationTracker = RecentApplicationTracker(),
    recipeStore: RecipeStore = RecipeStore(),
    historyStore: any ArrangementHistoryStoring = ArrangementHistoryStore(),
    suggestionRanker: SplitSuggestionRanker = SplitSuggestionRanker(),
    launchAtLogin: LaunchAtLoginController = LaunchAtLoginController(),
    pickerPanelCoordinator: any PickerPresenting = PickerPanelCoordinator(),
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init
  ) {
    self.accessibilityClient = accessibilityClient
    self.applicationVisibilityController = applicationVisibilityController
    self.permissionMonitor = permissionMonitor
    self.recentApplicationTracker = recentApplicationTracker
    self.recipeStore = recipeStore
    self.historyStore = historyStore
    self.suggestionRanker = suggestionRanker
    self.launchAtLogin = launchAtLogin
    self.pickerPanelCoordinator = pickerPanelCoordinator
    self.defaults = defaults
    self.now = now

    let storedLayout = defaults.string(forKey: DefaultsKey.selectedLayout)
    selectedLayout = SplitLayout(rawValue: storedLayout ?? "") ?? .twoColumns

    let storedRatio = defaults.string(forKey: DefaultsKey.selectedRatio)
    selectedRatio = SplitRatio(rawValue: storedRatio ?? "") ?? .equal

    if defaults.object(forKey: DefaultsKey.gap) == nil {
      gap = 8
    } else {
      gap = defaults.double(forKey: DefaultsKey.gap)
    }

    edgeToEdgeWindows = defaults.bool(forKey: DefaultsKey.edgeToEdgeWindows)

    if defaults.object(forKey: DefaultsKey.bringArrangedWindowsForward) == nil {
      bringArrangedWindowsForward = true
    } else {
      bringArrangedWindowsForward = defaults.bool(
        forKey: DefaultsKey.bringArrangedWindowsForward
      )
    }

    hideOtherApplicationsAfterSplit = defaults.bool(
      forKey: DefaultsKey.hideOtherApplicationsAfterSplit
    )

    if defaults.object(forKey: DefaultsKey.suggestionsEnabled) == nil {
      suggestionsEnabled = true
    } else {
      suggestionsEnabled = defaults.bool(forKey: DefaultsKey.suggestionsEnabled)
    }

    if let data = defaults.data(forKey: DefaultsKey.lastArrangement),
      let decoded = try? JSONDecoder().decode(SplitRecipe.self, from: data)
    {
      lastArrangement = decoded
    }

  }

  func refreshWindows() {
    enqueueRefresh()
  }

  func refreshSettings() {
    permissionGranted = accessibilityClient.hasPermission
    launchAtLogin.refresh()
  }

  private func enqueueRefresh() {
    refreshRequested = true
    isRefreshing = true
    guard refreshTask == nil else { return }

    refreshTask = Task { @MainActor [weak self] in
      await self?.runRefreshLoop()
    }
  }

  private func refreshWindowsForAction() async {
    await withCheckedContinuation { continuation in
      refreshWaiters.append(continuation)
      enqueueRefresh()
    }
  }

  private func runRefreshLoop() async {
    while refreshRequested {
      refreshRequested = false
      await performRefresh()
    }

    isRefreshing = false
    refreshTask = nil

    let waiters = refreshWaiters
    refreshWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  private func performRefresh() async {
    let wasAwaitingPermission = isAwaitingPermission
    permissionGranted = accessibilityClient.hasPermission

    if permissionGranted {
      permissionMonitor.stop()
      isAwaitingPermission = false
      let discoveredWindows = await accessibilityClient.discoverWindows(
        recentProcessIdentifiers: recentApplicationTracker.processIdentifiers
      )
      guard !refreshRequested else { return }
      let availableIDs = Set(discoveredWindows.map(\.id))
      let selectedWindowDisappeared = selectedWindowIDs.contains {
        !availableIDs.contains($0)
      }
      windows = discoveredWindows
      reconcileSelection(fillMissingSlots: !selectedWindowDisappeared)
      updateSuggestion()
      AppLogger.arrangement.debug(
        "Discovered \(self.windows.count, privacy: .public) eligible windows")
      if wasAwaitingPermission {
        setStatus("Accessibility access granted.", isError: false)
      }
      if selectedWindowDisappeared {
        setStatus("A selected window is no longer available.", isError: true)
      }
    } else {
      windows = []
      selectedWindowIDs = []
    }
  }

  func requestAccessibilityPermission() {
    permissionGranted = accessibilityClient.requestPermission()
    if permissionGranted {
      refreshWindows()
    } else {
      statusMessage = nil
      statusIsError = false
      isAwaitingPermission = true
      permissionMonitor.start(
        check: { [weak self] in
          self?.accessibilityClient.hasPermission ?? false
        },
        onGranted: { [weak self] in
          self?.refreshWindows()
        },
        onTimeout: { [weak self] in
          guard let self else { return }
          self.isAwaitingPermission = false
          self.setStatus(
            "Access is still off. Enable \(self.applicationDisplayName) in System Settings, then check again.",
            isError: true
          )
        }
      )
    }
  }

  func openAccessibilitySettings() {
    accessibilityClient.openAccessibilitySettings()
  }

  func showPicker() {
    pickerPanelCoordinator.show(model: self)
  }

  func dismissPicker() {
    pickerPanelCoordinator.dismiss()
  }

  func toggleWindow(_ window: WindowDescriptor) {
    if let index = selectedWindowIDs.firstIndex(of: window.id) {
      selectedWindowIDs.remove(at: index)
      return
    }

    if selectedWindowIDs.count == selectedLayout.slotCount {
      selectedWindowIDs.removeLast()
    }
    selectedWindowIDs.append(window.id)
  }

  func selectionNumber(for window: WindowDescriptor) -> Int? {
    selectedWindowIDs.firstIndex(of: window.id).map { $0 + 1 }
  }

  func quickSplit() {
    guard preparationTask == nil, !isArranging else { return }
    preparationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.preparationTask = nil }
      await self.refreshWindowsForAction()
      let windowIDs = self.defaultWindowIDs(count: 2)
      guard windowIDs.count == 2 else {
        self.setStatus("Open two resizable application windows first.", isError: true)
        self.showPicker()
        return
      }

      self.selectedLayout = .twoColumns
      self.selectedWindowIDs = windowIDs
      self.applySelection(closePanel: false, source: .quickSplit)
    }
  }

  func repeatLastSplit() {
    guard let lastArrangement else {
      setStatus("There is no previous split to repeat.", isError: true)
      showPicker()
      return
    }
    apply(lastArrangement, closePanel: false, source: .repeatLast)
  }

  func undo() {
    guard !isArranging else { return }
    isArranging = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await self.accessibilityClient.undo()
      let visibilityResult = self.applicationVisibilityController.undo()
      let completedResult = result.addingWarnings(visibilityResult.warnings)
      self.isArranging = false
      self.canUndo = self.accessibilityClient.hasUndo
        || self.applicationVisibilityController.hasUndo
      self.handle(completedResult, action: .restore)
    }
  }

  func saveRecipe(named rawName: String) {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      setStatus("Give the saved split a name.", isError: true)
      return
    }

    guard let recipe = recipe(name: name, from: selectedWindowIDs) else {
      setStatus("All selected applications need a bundle identifier.", isError: true)
      return
    }

    recipeStore.add(recipe)
    if let errorMessage = recipeStore.errorMessage {
      setStatus(errorMessage, isError: true)
    } else {
      setStatus("Saved “\(name)”.", isError: false)
      updateSuggestion()
    }
  }

  func deleteRecipe(_ recipe: SplitRecipe) {
    recipeStore.delete(recipe)
    if let errorMessage = recipeStore.errorMessage {
      setStatus(errorMessage, isError: true)
    }
    updateSuggestion()
  }

  func canApply(_ recipe: SplitRecipe) -> Bool {
    resolvedWindowIDs(for: recipe).count == recipe.slots.count
  }

  func apply(
    _ recipe: SplitRecipe,
    closePanel: Bool = false,
    source: ArrangementEvent.Source = .savedRecipe
  ) {
    guard preparationTask == nil, !isArranging else { return }
    preparationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.preparationTask = nil }
      await self.refreshWindowsForAction()
      let ids = self.resolvedWindowIDs(for: recipe)
      guard ids.count == recipe.slots.count else {
        self.setStatus("Open every application in “\(recipe.name)” first.", isError: true)
        return
      }

      self.selectedLayout = recipe.layout
      self.selectedRatio = recipe.ratio
      if let spacing = recipe.spacing {
        self.edgeToEdgeWindows = spacing.edgeToEdge
        self.gap = spacing.gap
      }
      self.selectedWindowIDs = ids
      self.applySelection(closePanel: closePanel, source: source)
    }
  }

  private func reconcileSelection(fillMissingSlots: Bool = true) {
    let availableIDs = Set(windows.map(\.id))
    selectedWindowIDs = selectedWindowIDs.filter { availableIDs.contains($0) }

    if selectedWindowIDs.count > selectedLayout.slotCount {
      selectedWindowIDs = Array(selectedWindowIDs.prefix(selectedLayout.slotCount))
    }

    if fillMissingSlots, selectedWindowIDs.count < selectedLayout.slotCount {
      let replacements = defaultWindowIDs(count: selectedLayout.slotCount)
        .filter { !selectedWindowIDs.contains($0) }
      selectedWindowIDs.append(
        contentsOf: replacements.prefix(selectedLayout.slotCount - selectedWindowIDs.count)
      )
    }
  }

  private func defaultWindowIDs(count: Int) -> [UUID] {
    var result: [UUID] = []
    var usedProcesses = Set<pid_t>()

    for window in windows where !usedProcesses.contains(window.processIdentifier) {
      result.append(window.id)
      usedProcesses.insert(window.processIdentifier)
      if result.count == count { return result }
    }

    for window in windows where !result.contains(window.id) {
      result.append(window.id)
      if result.count == count { return result }
    }

    return result
  }

  private func rememberLastArrangement(_ recipe: SplitRecipe) {
    lastArrangement = recipe
    if let data = try? JSONEncoder().encode(recipe) {
      defaults.set(data, forKey: DefaultsKey.lastArrangement)
    }
  }

  private func recipe(name: String, from windowIDs: [UUID]) -> SplitRecipe? {
    let selectedWindows = windowIDs.compactMap { id in windows.first { $0.id == id } }
    guard selectedWindows.count == selectedLayout.slotCount else { return nil }

    let slots = selectedWindows.compactMap { window -> SplitRecipe.Slot? in
      guard let bundleIdentifier = window.bundleIdentifier else { return nil }
      return SplitRecipe.Slot(
        bundleIdentifier: bundleIdentifier,
        applicationName: window.applicationName
      )
    }
    guard slots.count == selectedWindows.count else { return nil }

    return SplitRecipe(
      name: name,
      layout: selectedLayout,
      ratio: selectedRatio,
      slots: slots,
      spacing: currentSpacing
    )
  }

  private func resolvedWindowIDs(for recipe: SplitRecipe) -> [UUID] {
    var usedIDs = Set<UUID>()
    var result: [UUID] = []

    for slot in recipe.slots {
      guard
        let window = windows.first(where: {
          $0.bundleIdentifier == slot.bundleIdentifier && !usedIDs.contains($0.id)
        })
      else { return [] }

      usedIDs.insert(window.id)
      result.append(window.id)
    }

    return result
  }

  private func handle(
    _ result: ArrangementResult,
    action: ArrangementOperation = .arrange
  ) {
    setStatus(
      result.summary(for: action),
      isError: result.arrangedCount == 0 || !result.failures.isEmpty
    )
    for warning in result.warnings {
      AppLogger.arrangement.warning("Arrangement warning: \(warning, privacy: .public)")
    }
    if result.succeeded {
      AppLogger.arrangement.info("Arranged \(result.arrangedCount, privacy: .public) windows")
    } else {
      AppLogger.arrangement.error(
        "Arrangement completed with \(result.failures.count, privacy: .public) failures"
      )
      for failure in result.failures {
        AppLogger.arrangement.error("Arrangement failure: \(failure, privacy: .public)")
      }
    }
  }

  func setStatus(_ message: String, isError: Bool) {
    statusMessage = message
    statusIsError = isError
  }
}

extension AppModel {
  func applySelection(
    closePanel: Bool = false,
    source: ArrangementEvent.Source = .manual
  ) {
    guard canApplySelection else {
      setStatus("Choose exactly \(selectedLayout.slotCount) windows.", isError: true)
      return
    }

    let windowIDs = selectedWindowIDs
    let layout = selectedLayout
    let ratio = selectedRatio
    let requestedGap = edgeToEdgeWindows ? 0 : gap
    let rememberedRecipe = recipe(name: "Last Split", from: windowIDs)
    let visibilityCandidates = windows
    let selectedProcessIdentifiers = Set(
      visibilityCandidates
        .filter { windowIDs.contains($0.id) }
        .map(\.processIdentifier)
    )
    isArranging = true

    Task { @MainActor [weak self] in
      guard let self else { return }
      let preparation = self.applicationVisibilityController.prepareForArrangement(
        selectedProcessIdentifiers: selectedProcessIdentifiers
      )
      let result = await self.accessibilityClient.arrange(
        windowIDs: windowIDs,
        layout: layout,
        ratio: ratio,
        gap: requestedGap,
        bringWindowsForward: self.bringArrangedWindowsForward
      )
      let visibilityResult: ApplicationVisibilityResult
      if result.succeeded {
        visibilityResult = self.applicationVisibilityController.completeArrangement(
          selectedProcessIdentifiers: selectedProcessIdentifiers,
          candidates: visibilityCandidates,
          hideOtherApplications: self.hideOtherApplicationsAfterSplit
        )
      } else {
        visibilityResult = self.applicationVisibilityController.cancelArrangement()
      }
      let completedResult = result.addingWarnings(
        preparation.warnings + visibilityResult.warnings
      )
      self.isArranging = false
      self.canUndo = self.accessibilityClient.hasUndo
        || self.applicationVisibilityController.hasUndo
      self.handle(completedResult)

      if completedResult.succeeded {
        if let rememberedRecipe {
          self.rememberLastArrangement(rememberedRecipe)
          self.recordSuccessfulArrangement(rememberedRecipe, source: source)
        }
        if closePanel { self.dismissPicker() }
      }
    }
  }
}
