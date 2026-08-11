import SwiftUI

struct LayoutGlyph: View {
  let layout: SplitLayout

  var body: some View {
    GeometryReader { proxy in
      let frames = frames(in: proxy.size)
      ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
          .fill(index == 0 ? Color.accentColor : Color.secondary.opacity(0.42))
          .frame(width: frame.width, height: frame.height)
          .position(x: frame.midX, y: frame.midY)
      }
    }
    .accessibilityHidden(true)
  }

  private func frames(in size: CGSize) -> [CGRect] {
    let gap: CGFloat = 3
    switch layout {
    case .twoColumns:
      let width = (size.width - gap) / 2
      return [
        CGRect(x: 0, y: 0, width: width, height: size.height),
        CGRect(x: width + gap, y: 0, width: width, height: size.height),
      ]
    case .twoRows:
      let height = (size.height - gap) / 2
      return [
        CGRect(x: 0, y: 0, width: size.width, height: height),
        CGRect(x: 0, y: height + gap, width: size.width, height: height),
      ]
    case .threeColumns:
      let width = (size.width - (2 * gap)) / 3
      return (0..<3).map { index in
        CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
      }
    case .leadingWithStack:
      let leadingWidth = (size.width - gap) * 0.6
      let trailingWidth = size.width - leadingWidth - gap
      let stackedHeight = (size.height - gap) / 2
      return [
        CGRect(x: 0, y: 0, width: leadingWidth, height: size.height),
        CGRect(x: leadingWidth + gap, y: 0, width: trailingWidth, height: stackedHeight),
        CGRect(
          x: leadingWidth + gap,
          y: stackedHeight + gap,
          width: trailingWidth,
          height: stackedHeight
        ),
      ]
    }
  }
}

