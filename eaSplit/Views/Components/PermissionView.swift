import SwiftUI

struct PermissionView: View {
  let applicationName: String
  let isAwaitingPermission: Bool
  let statusMessage: String?
  let statusIsError: Bool
  let requestAccess: () -> Void
  let openSettings: () -> Void
  let refresh: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "rectangle.3.group.bubble.left")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(.tint)
        .symbolRenderingMode(.hierarchical)

      VStack(spacing: 6) {
        Text("Allow Window Control")
          .font(.title3.weight(.semibold))

        Text("\(applicationName) needs Accessibility access to move and resize only the windows you choose. Window information stays on this Mac.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 8) {
        if isAwaitingPermission {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Turn on “\(applicationName)” in System Settings…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Button(isAwaitingPermission ? "Request Again" : "Request Access", action: requestAccess)
          .buttonStyle(.borderedProminent)
          .controlSize(.large)

        HStack(spacing: 12) {
          Button("Open System Settings", action: openSettings)
          Button("Check Again", action: refresh)
        }
        .buttonStyle(.link)
      }

      if let statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(statusIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: 310)
    .padding(32)
  }
}
