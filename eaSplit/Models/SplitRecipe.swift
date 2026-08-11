import Foundation

struct SplitRecipe: Codable, Identifiable, Equatable, Sendable {
  struct Slot: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let applicationName: String
  }

  let id: UUID
  var name: String
  var layout: SplitLayout
  var ratio: SplitRatio
  var slots: [Slot]

  init(
    id: UUID = UUID(),
    name: String,
    layout: SplitLayout,
    ratio: SplitRatio,
    slots: [Slot]
  ) {
    self.id = id
    self.name = name
    self.layout = layout
    self.ratio = ratio
    self.slots = slots
  }
}

