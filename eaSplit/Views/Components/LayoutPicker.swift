import SwiftUI

struct LayoutPicker: View {
  @Binding var selection: SplitLayout

  var body: some View {
    if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: 8) {
        buttons
      }
    } else {
      buttons
    }
  }

  private var buttons: some View {
    HStack(spacing: 8) {
      ForEach(SplitLayout.allCases) { layout in
        LayoutOptionButton(layout: layout, isSelected: selection == layout) {
          selection = layout
        }
      }
    }
  }
}

