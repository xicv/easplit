import Foundation
import XCTest
@testable import eaSplit

@MainActor
final class RecipeStoreTests: XCTestCase {
  func testRecipesPersistAndReload() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("recipes.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let recipe = SplitRecipe(
      name: "Work Pair",
      layout: .twoColumns,
      ratio: .equal,
      slots: [
        .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
        .init(bundleIdentifier: "com.microsoft.teams2", applicationName: "Microsoft Teams"),
      ]
    )

    let store = RecipeStore(fileURL: fileURL)
    store.add(recipe)

    XCTAssertNil(store.errorMessage)
    XCTAssertEqual(store.recipes, [recipe])

    let reloaded = RecipeStore(fileURL: fileURL)
    XCTAssertNil(reloaded.errorMessage)
    XCTAssertEqual(reloaded.recipes, [recipe])
  }

  func testDeletingRecipeUpdatesDisk() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("recipes.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let recipe = SplitRecipe(
      name: "Writing",
      layout: .twoRows,
      ratio: .leading,
      slots: [
        .init(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
        .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
      ]
    )

    let store = RecipeStore(fileURL: fileURL)
    store.add(recipe)
    store.delete(recipe)

    let reloaded = RecipeStore(fileURL: fileURL)
    XCTAssertTrue(reloaded.recipes.isEmpty)
  }

  func testFailedWriteDoesNotChangeInMemoryRecipes() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let blockingFile = directory.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blockingFile)
    let store = RecipeStore(fileURL: blockingFile.appendingPathComponent("recipes.json"))
    let recipe = SplitRecipe(
      name: "Work",
      layout: .twoColumns,
      ratio: .equal,
      slots: [
        .init(bundleIdentifier: "com.apple.Safari", applicationName: "Safari"),
        .init(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
      ]
    )

    store.add(recipe)

    XCTAssertTrue(store.recipes.isEmpty)
    XCTAssertNotNil(store.errorMessage)
  }
}
