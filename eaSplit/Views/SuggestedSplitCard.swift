import SwiftUI

struct SuggestedSplitCard: View {
  let suggestion: SplitSuggestion
  let windows: [WindowDescriptor]
  let isEnabled: Bool
  let apply: () -> Void
  let suppress: () -> Void

  var body: some View {
    cardContent
      .padding(12)
      .modifier(SuggestionSurface())
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("suggested-split")
  }

  private var cardContent: some View {
    HStack(spacing: 12) {
      iconStack

      VStack(alignment: .leading, spacing: 3) {
        Text("Suggested Split")
          .font(.subheadline.weight(.semibold))

        Text(applicationNames)
          .font(.caption)
          .lineLimit(1)

        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Menu {
        Button("Don't Suggest This", systemImage: "eye.slash", action: suppress)
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Suggestion options")

      Button("Split", action: apply)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!isEnabled)
        .accessibilityLabel("Split \(applicationNames)")
        .accessibilityIdentifier("apply-suggestion")
    }
  }

  private var iconStack: some View {
    HStack(spacing: -7) {
      ForEach(windows.prefix(3)) { window in
        Image(nsImage: window.icon)
          .resizable()
          .scaledToFit()
          .frame(width: 26, height: 26)
          .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      }
    }
    .frame(minWidth: 30)
    .accessibilityHidden(true)
  }

  private var applicationNames: String {
    suggestion.signature.applications.map(\.applicationName).joined(separator: " + ")
  }

  private var detail: String {
    "\(reasonLabel) · \(suggestion.signature.layout.detail) · \(ratioLabel)"
  }

  private var reasonLabel: String {
    switch suggestion.reason {
    case .saved(let name): "Saved “\(name)”"
    case .frequentlyUsed: "Frequently used"
    }
  }

  private var ratioLabel: String {
    suggestion.signature.layout.slotCount == 3
      ? "Equal thirds"
      : suggestion.signature.ratio.name
  }
}

private struct SuggestionSurface: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(
        .regular,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
    } else {
      content
        .background(
          .regularMaterial,
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }
  }
}
