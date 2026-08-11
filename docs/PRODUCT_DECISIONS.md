# eaSplit product decisions

## Product promise

eaSplit turns a small set of already-open windows into a useful layout with one
short interaction. It is a picker, not an automatic tiling window manager.

The default path is:

1. Open the menu-bar picker.
2. Accept the two most recently used applications or choose different windows.
3. Choose a layout and press **Split**.

After that, a user can save the application combination, repeat the last split,
or assign a global shortcut for a two-window quick split.

## First release scope

Included:

- Two columns, two rows, three columns, and one-leading-plus-two-stacked.
- 50/50 or 60/40 allocation where the layout has a primary region.
- A small configurable gap or edge-to-edge placement.
- Explicit window ordering: the numbered selection is the slot order.
- Recipes that remember application bundle identifiers, layout, and ratio.
- Undo for the most recent arrangement in the current process.
- User-configured global shortcuts and native launch at login.

Intentionally excluded:

- Automatic continuous retiling.
- Moving windows between Spaces.
- Private APIs, scripting additions, and injected helpers.
- Accounts, analytics, cloud sync, and a licensing stub.
- Launching applications or recreating documents from a recipe.
- Arbitrary grid editors and a large catalogue of niche layouts.

The payment model remains a one-time direct-purchase hypothesis. Licensing is
not scaffolded until the core workflow has been tested with users and a real
payment/licensing provider is selected.

As of 11 August 2026, comparable direct-sale utilities remain in the roughly
USD $15 one-time range (Moom and Swish). The working launch hypothesis is USD
$12–15 with a free trial. Lemon Squeezy is the current simplest license-key
candidate; it supports single-payment products and license activation without
eaSplit having to invent a licensing backend. This is a commercial direction,
not an implementation decision: there will be no fake checkout, update feed, or
licensing endpoints in the app.

## Interface model

The menu-bar window is the primary surface. A global shortcut opens the same
SwiftUI picker in a small keyable AppKit panel, because SwiftUI does not expose a
public API for programmatically presenting a `MenuBarExtra` window. Settings are
limited to defaults, gaps, shortcuts, launch at login, and Accessibility status.

System materials, typography, spacing, and controls provide most of the visual
design. On macOS 26, the four layout choices use `GlassEffectContainer` and
interactive glass surfaces. macOS 15 has a restrained material fallback.

## Native implementation boundary

- SwiftUI owns scenes, views, observable state, settings, and menu-bar content.
- A narrow `NSPanel` coordinator provides shortcut-driven presentation.
- `NSWorkspace` provides running applications and recency signals.
- Public `AXUIElement` attributes enumerate, move, and resize eligible windows.
- Geometry is a pure, tested component using Accessibility's top-down screen
  coordinates.
- Recipes are JSON in Application Support. Window titles are never persisted or
  logged.
- `SMAppService.mainApp` implements launch at login.

## Distribution decision

The first release targets direct Developer ID-signed and notarized distribution,
with App Sandbox disabled and Hardened Runtime enabled. Apple requires App
Sandbox for the Mac App Store, while Apple's sandbox guidance identifies
Accessibility APIs as incompatible activity. Those two constraints conflict with
eaSplit's core ability to resize other applications, so a new Mac App Store build
is not a credible day-one target.

References:

- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple: Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Apple AXUIElement header](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Apple GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Apple SMAppService registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)
- [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

## Open-source research boundary

- [Rectangle](https://github.com/rxhanson/Rectangle) validates a focused,
  shortcut-led Swift window manager and simple preferences. It is MIT licensed.
- [Loop](https://github.com/MrKai77/Loop) demonstrates the value of visual
  direction previews and discoverable interactions. It is GPL-3.0 licensed, so
  no source was copied.
- [Amethyst](https://github.com/ianyh/Amethyst) demonstrates more complex
  automatic tiling and main-pane layouts. eaSplit deliberately avoids that
  always-on complexity. It is MIT licensed.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) provides
  the only third-party runtime code currently used, pinned to 3.0.1 under MIT.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) documents a crucial
  performance constraint: Accessibility calls can block on an unresponsive
  target application. eaSplit responds by moving discovery and frame changes
  off the main actor and bounding per-application AX messaging time.

The current implementation also verifies the final frame after a move. Setter
success alone is not treated as success because applications may enforce a
minimum size or otherwise clamp the requested frame.

The project uses these products as behavioral references only. No source was
copied from another window manager.
