import CoreGraphics

enum LayoutEngineError: Error, Equatable {
  case invalidBounds
}

struct LayoutEngine: Sendable {
  func frames(
    for layout: SplitLayout,
    in visibleFrame: CGRect,
    ratio: SplitRatio,
    gap requestedGap: CGFloat
  ) throws -> [CGRect] {
    guard visibleFrame.width > 0, visibleFrame.height > 0 else {
      throw LayoutEngineError.invalidBounds
    }

    let gap = max(0, min(requestedGap, min(visibleFrame.width, visibleFrame.height) / 4))
    let workArea = visibleFrame.insetBy(dx: gap, dy: gap)

    guard workArea.width > 0, workArea.height > 0 else {
      throw LayoutEngineError.invalidBounds
    }

    switch layout {
    case .twoColumns:
      return twoColumns(in: workArea, ratio: ratio.fraction, gap: gap)
    case .twoRows:
      return twoRows(in: workArea, ratio: ratio.fraction, gap: gap)
    case .threeColumns:
      return threeColumns(in: workArea, gap: gap)
    case .leadingWithStack:
      return leadingWithStack(in: workArea, ratio: ratio.fraction, gap: gap)
    }
  }

  private func twoColumns(in bounds: CGRect, ratio: CGFloat, gap: CGFloat) -> [CGRect] {
    let usableWidth = max(0, bounds.width - gap)
    let leadingWidth = floor(usableWidth * ratio)
    let trailingWidth = usableWidth - leadingWidth

    return [
      rounded(CGRect(x: bounds.minX, y: bounds.minY, width: leadingWidth, height: bounds.height)),
      rounded(CGRect(
        x: bounds.minX + leadingWidth + gap,
        y: bounds.minY,
        width: trailingWidth,
        height: bounds.height
      )),
    ]
  }

  private func twoRows(in bounds: CGRect, ratio: CGFloat, gap: CGFloat) -> [CGRect] {
    let usableHeight = max(0, bounds.height - gap)
    let topHeight = floor(usableHeight * ratio)
    let bottomHeight = usableHeight - topHeight

    return [
      rounded(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: topHeight)),
      rounded(CGRect(
        x: bounds.minX,
        y: bounds.minY + topHeight + gap,
        width: bounds.width,
        height: bottomHeight
      )),
    ]
  }

  private func threeColumns(in bounds: CGRect, gap: CGFloat) -> [CGRect] {
    let usableWidth = max(0, bounds.width - (2 * gap))
    let columnWidth = floor(usableWidth / 3)
    let finalWidth = usableWidth - (2 * columnWidth)

    return [
      rounded(CGRect(x: bounds.minX, y: bounds.minY, width: columnWidth, height: bounds.height)),
      rounded(CGRect(
        x: bounds.minX + columnWidth + gap,
        y: bounds.minY,
        width: columnWidth,
        height: bounds.height
      )),
      rounded(CGRect(
        x: bounds.minX + (2 * (columnWidth + gap)),
        y: bounds.minY,
        width: finalWidth,
        height: bounds.height
      )),
    ]
  }

  private func leadingWithStack(in bounds: CGRect, ratio: CGFloat, gap: CGFloat) -> [CGRect] {
    let columns = twoColumns(in: bounds, ratio: ratio, gap: gap)
    let leading = columns[0]
    let trailing = columns[1]
    let usableHeight = max(0, trailing.height - gap)
    let topHeight = floor(usableHeight / 2)
    let bottomHeight = usableHeight - topHeight

    return [
      leading,
      rounded(CGRect(x: trailing.minX, y: trailing.minY, width: trailing.width, height: topHeight)),
      rounded(CGRect(
        x: trailing.minX,
        y: trailing.minY + topHeight + gap,
        width: trailing.width,
        height: bottomHeight
      )),
    ]
  }

  private func rounded(_ frame: CGRect) -> CGRect {
    CGRect(
      x: frame.origin.x.rounded(),
      y: frame.origin.y.rounded(),
      width: frame.size.width.rounded(),
      height: frame.size.height.rounded()
    )
  }
}
