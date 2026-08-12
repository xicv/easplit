import AppKit
import SwiftUI

enum PickerPresentation {
  case menuBar
  case panel
}

struct SplitPickerView: View {
  @Bindable var model: AppModel
  let presentation: PickerPresentation

  @State private var showingSaveSheet = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      if model.permissionGranted {
        pickerContent
      } else {
        Spacer()
        PermissionView(
          applicationName: model.applicationDisplayName,
          isAwaitingPermission: model.isAwaitingPermission,
          statusMessage: model.statusMessage,
          statusIsError: model.statusIsError,
          requestAccess: model.requestAccessibilityPermission,
          openSettings: model.openAccessibilitySettings,
          refresh: model.refreshWindows
        )
        Spacer()
      }
    }
    .frame(width: 420, height: 560)
    .background(background)
    .clipShape(RoundedRectangle(cornerRadius: presentation == .panel ? 16 : 0, style: .continuous))
    .task { model.refreshWindows() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      model.refreshWindows()
    }
    .onExitCommand {
      if presentation == .panel { model.dismissPicker() }
    }
    .sheet(isPresented: $showingSaveSheet) {
      SaveRecipeView(save: model.saveRecipe)
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Split Windows")
          .font(.headline)
        Text("Choose \(model.selectedLayout.slotCount) windows")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(action: model.refreshWindows) {
        if model.isRefreshing {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "arrow.clockwise")
        }
      }
      .buttonStyle(.borderless)
      .disabled(model.isRefreshing)
      .help("Refresh windows")
      .accessibilityIdentifier("refresh-windows")

      SettingsLink {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help("Settings")
      .accessibilityIdentifier("open-settings")

      Menu {
        Button("Repeat Last Split", systemImage: "repeat", action: model.repeatLastSplit)
          .disabled(!model.canRepeatLastSplit)

        Divider()

        Button("About eaSplit", systemImage: "info.circle") {
          NSApp.activate(ignoringOtherApps: true)
          NSApp.orderFrontStandardAboutPanel()
        }

        Button("Quit eaSplit", systemImage: "power") {
          NSApp.terminate(nil)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("More")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var pickerContent: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          LayoutPicker(selection: $model.selectedLayout)

          windowsSection

          if !model.recipeStore.recipes.isEmpty {
            recipesSection
          }
        }
        .padding(16)
      }
      .disabled(model.isArranging)

      Divider()
      actionBar
    }
  }

  private var windowsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Windows")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(model.selectedWindowIDs.count) of \(model.selectedLayout.slotCount)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if model.windows.isEmpty {
        ContentUnavailableView(
          "No Resizable Windows",
          systemImage: "macwindow",
          description: Text("Open an application window, then refresh.")
        )
        .frame(maxWidth: .infinity, minHeight: 150)
      } else {
        LazyVStack(spacing: 3) {
          ForEach(model.windows) { window in
            WindowRow(window: window, selectionNumber: model.selectionNumber(for: window)) {
              model.toggleWindow(window)
            }
          }
        }
      }
    }
  }

  private var recipesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Saved")
        .font(.subheadline.weight(.semibold))

      ForEach(model.recipeStore.recipes) { recipe in
        RecipeRow(
          recipe: recipe,
          isAvailable: model.canApply(recipe),
          apply: { model.apply(recipe, closePanel: presentation == .panel) },
          delete: { model.deleteRecipe(recipe) }
        )
      }
    }
  }

  private var actionBar: some View {
    VStack(spacing: 9) {
      if let statusMessage = model.statusMessage {
        HStack(spacing: 6) {
          Image(
            systemName: model.statusIsError
              ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
          Text(statusMessage)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
        }
        .font(.caption)
        .foregroundStyle(model.statusIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
      }

      HStack(spacing: 10) {
        Button("Undo", action: model.undo)
          .disabled(!model.canUndo || model.isArranging)
          .accessibilityIdentifier("undo-arrangement")

        Button {
          showingSaveSheet = true
        } label: {
          Label("Save", systemImage: "bookmark")
        }
        .disabled(!model.canApplySelection)
        .accessibilityIdentifier("save-recipe")

        Spacer()

        if model.selectedLayout == .threeColumns {
          Text("Equal thirds")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Picker("Ratio", selection: $model.selectedRatio) {
            ForEach(SplitRatio.allCases) { ratio in
              Text(ratio.name).tag(ratio)
            }
          }
          .labelsHidden()
          .frame(width: 92)
        }

        Button {
          model.applySelection(closePanel: presentation == .panel)
        } label: {
          Group {
            if model.isArranging {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Split")
            }
          }
          .frame(minWidth: 48)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canApplySelection)
        .accessibilityIdentifier("apply-split")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var background: some ShapeStyle {
    presentation == .panel ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear)
  }
}
