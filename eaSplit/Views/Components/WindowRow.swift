import SwiftUI

struct WindowRow: View {
  let window: WindowDescriptor
  let selectionNumber: Int?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 11) {
        Image(nsImage: window.icon)
          .resizable()
          .scaledToFit()
          .frame(width: 28, height: 28)

        VStack(alignment: .leading, spacing: 2) {
          Text(window.applicationName)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)

          Text(window.displayTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer(minLength: 8)

        ZStack {
          Circle()
            .fill(selectionNumber == nil ? Color.secondary.opacity(0.12) : Color.accentColor)
          if let selectionNumber {
            Text(selectionNumber.formatted())
              .font(.caption2.bold())
              .foregroundStyle(.white)
          }
        }
        .frame(width: 22, height: 22)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selectionNumber == nil ? Color.clear : Color.accentColor.opacity(0.10),
      in: RoundedRectangle(cornerRadius: 9, style: .continuous)
    )
    .accessibilityLabel("\(window.applicationName), \(window.displayTitle)")
    .accessibilityValue(selectionNumber.map { "Slot \($0)" } ?? "Not selected")
    .accessibilityIdentifier("window-\(window.id.uuidString)")
  }
}
