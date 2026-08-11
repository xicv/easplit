import SwiftUI

struct SaveRecipeView: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var nameIsFocused: Bool
  @State private var name = ""

  let save: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Save Split")
          .font(.title2.weight(.semibold))
        Text("Use this layout again when the same applications are running.")
          .foregroundStyle(.secondary)
      }

      TextField("Name, for example Work Pair", text: $name)
        .textFieldStyle(.roundedBorder)
        .focused($nameIsFocused)
        .onSubmit(saveAndDismiss)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
        Button("Save", action: saveAndDismiss)
          .buttonStyle(.borderedProminent)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(22)
    .frame(width: 390)
    .onAppear { nameIsFocused = true }
  }

  private func saveAndDismiss() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    save(trimmed)
    dismiss()
  }
}

