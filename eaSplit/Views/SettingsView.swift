import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel

  @State private var showingResetSuggestionsConfirmation = false

  var body: some View {
    TabView {
      generalSettings
        .tabItem { Label("General", systemImage: "gearshape") }

      shortcutSettings
        .tabItem { Label("Shortcuts", systemImage: "keyboard") }
    }
    .frame(width: 520, height: 430)
    .scenePadding()
    .onAppear {
      model.dismissPicker()
      model.refreshSettings()
    }
    .confirmationDialog(
      "Reset learned suggestions?",
      isPresented: $showingResetSuggestionsConfirmation
    ) {
      Button("Reset Learned Suggestions", role: .destructive) {
        model.resetSuggestions()
      }
    } message: {
      Text("eaSplit will forget frequently used combinations. Saved splits are not removed.")
    }
  }

  private var generalSettings: some View {
    Form {
      Section("Arrangement") {
        Picker("Default layout", selection: $model.selectedLayout) {
          ForEach(SplitLayout.allCases) { layout in
            Text(layout.detail).tag(layout)
          }
        }

        Picker("Default ratio", selection: $model.selectedRatio) {
          ForEach(SplitRatio.allCases) { ratio in
            Text(ratio.name).tag(ratio)
          }
        }
        .disabled(model.selectedLayout == .threeColumns)

        Toggle("Fill screen edge to edge", isOn: $model.edgeToEdgeWindows)
          .accessibilityIdentifier("edge-to-edge-windows")

        Text("Removes space between windows and the usable screen edges.")
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Text("Window gap")
          Slider(value: $model.gap, in: 0...32, step: 1)
          Text(model.edgeToEdgeWindows ? "None" : "\(Int(model.gap)) pt")
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(width: 38, alignment: .trailing)
        }
        .disabled(model.edgeToEdgeWindows)

        Toggle(
          "Bring split windows forward",
          isOn: $model.bringArrangedWindowsForward
        )
        .accessibilityIdentifier("bring-split-windows-forward")

        Text("Raises the selected windows after every split. The first selected window receives keyboard focus.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Focus") {
        Toggle(
          "Hide other apps after splitting",
          isOn: $model.hideOtherApplicationsAfterSplit
        )
        .accessibilityIdentifier("hide-other-apps-after-splitting")

        Text("Keeps the selected applications visible and hides other visible apps. Apps stay running; Undo restores only the apps hidden by eaSplit. This applies across all Spaces.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Suggestions") {
        Toggle("Suggest frequent splits", isOn: $model.suggestionsEnabled)
          .accessibilityIdentifier("suggest-frequent-splits")

        Text("Learns only from successful eaSplit actions. Application combinations stay on this Mac; window titles are never saved.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Button("Reset Learned Suggestions…") {
          showingResetSuggestionsConfirmation = true
        }
      }

      Section("Startup") {
        Toggle(
          "Launch eaSplit at login",
          isOn: Binding(
            get: { model.launchAtLogin.isEnabled },
            set: { isEnabled in
              model.launchAtLogin.setEnabled(isEnabled)
            }
          )
        )

        LabeledContent("Status", value: model.launchAtLogin.statusDescription)

        if model.launchAtLogin.requiresApproval {
          VStack(alignment: .leading, spacing: 8) {
            Text("macOS needs your approval before eaSplit can open at login.")
              .font(.caption)
              .foregroundStyle(.secondary)

            Button("Open Login Items Settings", action: model.launchAtLogin.openSystemSettings)
          }
        }

        if let errorMessage = model.launchAtLogin.errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Accessibility") {
        LabeledContent("Window control") {
          if model.permissionGranted {
            Text("Allowed")
              .foregroundStyle(.green)
          } else {
            Text("Not allowed")
              .foregroundStyle(.secondary)
          }
        }

        HStack {
          Button("Open System Settings", action: model.openAccessibilitySettings)
          Button("Refresh", action: model.refreshWindows)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var shortcutSettings: some View {
    Form {
      Section("Global Shortcuts") {
        KeyboardShortcuts.Recorder("Open picker", name: .openPicker)
        KeyboardShortcuts.Recorder("Quick split", name: .quickSplit)
        KeyboardShortcuts.Recorder("Repeat last split", name: .repeatLastSplit)
      }

      Section {
        Text(
          "Shortcuts are intentionally unset until you choose them, so eaSplit never takes over an existing system shortcut."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}
