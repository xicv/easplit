import SwiftUI

struct RecipeRow: View {
  let recipe: SplitRecipe
  let isAvailable: Bool
  let apply: () -> Void
  let delete: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      LayoutGlyph(layout: recipe.layout)
        .frame(width: 34, height: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(recipe.name)
          .font(.callout.weight(.medium))
          .lineLimit(1)
        Text(recipe.slots.map(\.applicationName).joined(separator: " + "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Button("Apply", action: apply)
        .disabled(!isAvailable)
        .accessibilityIdentifier("apply-recipe-\(recipe.id.uuidString)")

      Menu {
        Button("Delete", role: .destructive, action: delete)
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .padding(.vertical, 4)
  }
}
