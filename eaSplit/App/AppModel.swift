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
    static let lastArrangement = "lastArrangement"
  }

  private let accessibilityClient: AccessibilityWindowClient
  private let permissionMonitor: AccessibilityPermissionMonitor
  private let recentApplicationTracker: RecentApplicationTracker
  private let pickerPanelCoordinator: PickerPanelCoordinator
  private var hotKeyService: HotKeyService?
  private var lastArrangement: SplitRecipe?
  private var refreshTask: Task<Void, Never>?
  private var preparationTask: Task<Void, Never>?
  private var refreshGeneration = 0

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

  var selectedLayout: SplitLayout {
    didSet {
      UserDefaults.standard.set(selectedLayout.rawValue, forKey: DefaultsKey.selectedLayout)
      reconcileSelection()
    }
  }

  var selectedRatio: SplitRatio {
    didSet {
      UserDefaults.standard.set(selectedRatio.rawValue, forKey: DefaultsKey.selectedRatio)
    }
  }

  var gap: Double {
    didSet {
      let clamped = min(max(gap, 0), 32)
      if clamped != gap {
        gap = clamped
        return
      }
      UserDefaults.standard.set(gap, forKey: DefaultsKey.gap)
    }
  }

  var edgeToEdgeWindows: Bool {
    didSet {
      UserDefaults.standard.set(edgeToEdgeWindows, forKey: DefaultsKey.edgeToEdgeWindows)
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

  var applicationDisplayName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "eaSplit"
  }

  init(
    accessibilityClient: AccessibilityWindowClient = AccessibilityWindowClient(),
    permissionMonitor: AccessibilityPermissionMonitor = AccessibilityPermissionMonitor(),
    recentApplicationTracker: RecentApplicationTracker = RecentApplicationTracker(),
    recipeStore: RecipeStore = RecipeStore(),
    launchAtLogin: LaunchAtLoginController = LaunchAtLoginController(),
    pickerPanelCoordinator: PickerPanelCoordinator = PickerPanelCoordinator()
  ) {
    self.accessibilityClient = accessibilityClient
    self.permissionMonitor = permissionMonitor
    self.recentApplicationTracker = recentApplicationTracker
    self.recipeStore = recipeStore
    self.launchAtLogin = launchAtLogin
    self.pickerPanelCoordinator = pickerPanelCoordinator

    let storedLayout = UserDefaults.standard.string(forKey: DefaultsKey.selectedLayout)
    selectedLayout = SplitLayout(rawValue: storedLayout ?? "") ?? .twoColumns

    let storedRatio = UserDefaults.standard.string(forKey: DefaultsKey.selectedRatio)
    selectedRatio = SplitRatio(rawValue: storedRatio ?? "") ?? .equal

    if UserDefaults.standard.object(forKey: DefaultsKey.gap) == nil {
      gap = 8
    } else {
      gap = UserDefaults.standard.double(forKey: DefaultsKey.gap)
    }

    edgeToEdgeWindows = UserDefaults.standard.bool(forKey: DefaultsKey.edgeToEdgeWindows)

    if let data = UserDefaults.standard.data(forKey: DefaultsKey.lastArrangement),
      let decoded = try? JSONDecoder().decode(SplitRecipe.self, from: data)
    {
      lastArrangement = decoded
    }

    hotKeyService = HotKeyService(
      onOpenPicker: { [weak self] in self?.showPicker() },
      onQuickSplit: { [weak self] in self?.quickSplit() },
      onRepeatLastSplit: { [weak self] in self?.repeatLastSplit() }
    )

    refreshWindows()
  }

  func refreshWindows() {
    refreshTask?.cancel()
    refreshGeneration += 1
    let generation = refreshGeneration
    isRefreshing = true
    refreshTask = Task { @MainActor [weak self] in
      await self?.refreshWindows(generation: generation)
    }
  }

  private func refreshWindowsForAction() async {
    refreshTask?.cancel()
    refreshGeneration += 1
    let generation = refreshGeneration
    isRefreshing = true
    await refreshWindows(generation: generation)
  }

  private func refreshWindows(generation: Int) async {
    defer {
      if generation == refreshGeneration {
        isRefreshing = false
        refreshTask = nil
      }
    }

    let wasAwaitingPermission = isAwaitingPermission
    permissionGranted = accessibilityClient.hasPermission
    launchAtLogin.refresh()

    if permissionGranted {
      permissionMonitor.stop()
      isAwaitingPermission = false
      let discoveredWindows = await accessibilityClient.discoverWindows(
        recentProcessIdentifiers: recentApplicationTracker.processIdentifiers
      )
      guard !Task.isCancelled, generation == refreshGeneration else { return }
      windows = discoveredWindows
      reconcileSelection()
      AppLogger.arrangement.debug(
        "Discovered \(self.windows.count, privacy: .public) eligible windows")
      if wasAwaitingPermission {
        setStatus("Accessibility access granted.", isError: false)
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

  func applySelection(closePanel: Bool = false) {
    guard canApplySelection else {
      setStatus("Choose exactly \(selectedLayout.slotCount) windows.", isError: true)
      return
    }

    let windowIDs = selectedWindowIDs
    let layout = selectedLayout
    let ratio = selectedRatio
    let requestedGap = edgeToEdgeWindows ? 0 : gap
    let rememberedRecipe = recipe(name: "Last Split", from: windowIDs)
    isArranging = true

    Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await self.accessibilityClient.arrange(
        windowIDs: windowIDs,
        layout: layout,
        ratio: ratio,
        gap: requestedGap
      )
      self.isArranging = false
      self.canUndo = self.accessibilityClient.hasUndo
      self.handle(result)

      if result.arrangedCount > 0 {
        if let rememberedRecipe {
          self.rememberLastArrangement(rememberedRecipe)
        }
        if closePanel { self.dismissPicker() }
      }
    }
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
      self.applySelection(closePanel: false)
    }
  }

  func repeatLastSplit() {
    guard let lastArrangement else {
      setStatus("There is no previous split to repeat.", isError: true)
      showPicker()
      return
    }
    apply(lastArrangement, closePanel: false)
  }

  func undo() {
    guard !isArranging else { return }
    isArranging = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await self.accessibilityClient.undo()
      self.isArranging = false
      self.canUndo = self.accessibilityClient.hasUndo
      self.handle(result)
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
    }
  }

  func deleteRecipe(_ recipe: SplitRecipe) {
    recipeStore.delete(recipe)
    if let errorMessage = recipeStore.errorMessage {
      setStatus(errorMessage, isError: true)
    }
  }

  func canApply(_ recipe: SplitRecipe) -> Bool {
    resolvedWindowIDs(for: recipe).count == recipe.slots.count
  }

  func apply(_ recipe: SplitRecipe, closePanel: Bool = false) {
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
      self.selectedWindowIDs = ids
      self.applySelection(closePanel: closePanel)
    }
  }

  private func reconcileSelection() {
    let availableIDs = Set(windows.map(\.id))
    selectedWindowIDs = selectedWindowIDs.filter { availableIDs.contains($0) }

    if selectedWindowIDs.count > selectedLayout.slotCount {
      selectedWindowIDs = Array(selectedWindowIDs.prefix(selectedLayout.slotCount))
    }

    if selectedWindowIDs.count < selectedLayout.slotCount {
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
      UserDefaults.standard.set(data, forKey: DefaultsKey.lastArrangement)
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

    return SplitRecipe(name: name, layout: selectedLayout, ratio: selectedRatio, slots: slots)
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

  private func handle(_ result: ArrangementResult) {
    setStatus(result.summary, isError: result.arrangedCount == 0 || !result.failures.isEmpty)
    if result.succeeded {
      AppLogger.arrangement.info("Arranged \(result.arrangedCount, privacy: .public) windows")
    } else {
      AppLogger.arrangement.error(
        "Arrangement completed with \(result.failures.count, privacy: .public) failures"
      )
    }
  }

  private func setStatus(_ message: String, isError: Bool) {
    statusMessage = message
    statusIsError = isError
  }
}
