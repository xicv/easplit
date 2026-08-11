import Foundation
import Observation

@MainActor
@Observable
final class RecipeStore {
  private(set) var recipes: [SplitRecipe] = []
  private(set) var errorMessage: String?

  private let fileURL: URL
  private let fileManager: FileManager

  init(fileURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager

    if let fileURL {
      self.fileURL = fileURL
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      self.fileURL =
        applicationSupport
        .appendingPathComponent("eaSplit", isDirectory: true)
        .appendingPathComponent("recipes.json", isDirectory: false)
    }

    load()
  }

  func add(_ recipe: SplitRecipe) {
    let previousRecipes = recipes
    recipes.append(recipe)
    if !persist() {
      recipes = previousRecipes
    }
  }

  func delete(_ recipe: SplitRecipe) {
    let previousRecipes = recipes
    recipes.removeAll { $0.id == recipe.id }
    if !persist() {
      recipes = previousRecipes
    }
  }

  private func load() {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }

    do {
      let data = try Data(contentsOf: fileURL)
      recipes = try JSONDecoder().decode([SplitRecipe].self, from: data)
      errorMessage = nil
    } catch {
      errorMessage = "Saved layouts could not be read: \(error.localizedDescription)"
    }
  }

  @discardableResult
  private func persist() -> Bool {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(recipes)
      try data.write(to: fileURL, options: .atomic)
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Saved layouts could not be written: \(error.localizedDescription)"
      return false
    }
  }
}
