import SwiftUI

struct LayoutOptionButton: View {
  let layout: SplitLayout
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        LayoutGlyph(layout: layout)
          .frame(width: 46, height: 32)

        Text(layout.name)
          .font(.caption)
          .fontWeight(isSelected ? .semibold : .regular)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .modifier(LayoutOptionSurface(isSelected: isSelected))
    .accessibilityLabel(layout.detail)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct LayoutOptionSurface: ViewModifier {
  let isSelected: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(
        isSelected
          ? .regular.tint(.accentColor).interactive()
          : .regular.interactive(),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
    } else {
      content.background(
        isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(
            isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.16),
            lineWidth: 1
          )
      }
    }
  }
}

