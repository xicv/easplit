import CoreGraphics

enum SplitLayout: String, CaseIterable, Codable, Identifiable, Sendable {
  case twoColumns
  case twoRows
  case threeColumns
  case leadingWithStack

  var id: String { rawValue }

  var name: String {
    switch self {
    case .twoColumns: "Columns"
    case .twoRows: "Rows"
    case .threeColumns: "Three"
    case .leadingWithStack: "Focus"
    }
  }

  var detail: String {
    switch self {
    case .twoColumns: "Side by side"
    case .twoRows: "Top and bottom"
    case .threeColumns: "Three equal columns"
    case .leadingWithStack: "One large, two stacked"
    }
  }

  var slotCount: Int {
    switch self {
    case .twoColumns, .twoRows: 2
    case .threeColumns, .leadingWithStack: 3
    }
  }
}

enum SplitRatio: String, CaseIterable, Codable, Identifiable, Sendable {
  case equal
  case leading

  var id: String { rawValue }

  var name: String {
    switch self {
    case .equal: "50 / 50"
    case .leading: "60 / 40"
    }
  }

  var fraction: CGFloat {
    switch self {
    case .equal: 0.5
    case .leading: 0.6
    }
  }
}

