# eaSplit

eaSplit is a native macOS menu-bar utility for arranging two or three chosen
application windows into a repeatable layout.

Private beta: <https://xicv.github.io/easplit/>

The product is intentionally focused on one workflow: choose windows, choose a
split, and reuse it. It is built for direct, Developer ID-signed and notarized
distribution because controlling other applications through the macOS
Accessibility API is incompatible with the Mac App Store sandbox.

The agreed product scope, UI rationale, native boundaries, and open-source
research are recorded in [`docs/PRODUCT_DECISIONS.md`](docs/PRODUCT_DECISIONS.md).

## Current working slice

- Native SwiftUI `MenuBarExtra` picker
- Shortcut-opened AppKit panel using the same SwiftUI content
- Real Accessibility permission request and window enumeration
- Equal columns, equal rows, three columns, and focus-plus-stack layouts
- 50/50 and 60/40 ratios with configurable gaps or edge-to-edge placement
- Recent-application ordering and automatic default selection
- Local frequent-split suggestions learned from successful arrangements
- Saved application recipes stored locally as JSON
- Repeat-last-split and undo
- Default-on foreground activation for every successfully arranged window
- Optional focus mode that hides other visible apps and restores them with Undo
- Configurable global keyboard shortcuts
- Native launch-at-login control

Full-screen, minimized, dialog, fixed-size, and nonstandard windows are excluded.
Recipes currently arrange applications that are already running. eaSplit does
not use private APIs and does not move windows between Spaces.

## Requirements

- macOS 15 or later
- Xcode 26.6
- XcodeGen 2.46.0
- Accessibility permission for eaSplit

## Build and run

```sh
./script/build_and_run.sh
```

The script regenerates `eaSplit.xcodeproj`, builds into project-local Derived
Data, stages the signed development bundle at
`~/Applications/eaSplit Development.app`, stops an existing instance, and
launches the staged app. The stable standard location lets macOS associate its
Accessibility approval with the correct binary. The Codex Run action is wired
to the same entrypoint.

Debug builds use the separate `com.xicao.easplit.debug` bundle identifier and
appear in Privacy & Security as **eaSplit Development**. This keeps local
Accessibility approval stable across rebuilds and separate from the production
Developer ID application.

Run the canonical local quality gate with:

```sh
./script/quality.sh
```

It checks only modified or created Swift files with SwiftLint, verifies the
generated project is current, runs tests with coverage, enforces the production
coverage floor, and runs Release static analysis. Hosted CI calls the same
script.

## Distribution status

The repository includes fail-closed local and GitHub-hosted Developer ID
archive, disk-image signing, notarization, stapling, Gatekeeper, checksum, and
artifact-verification workflows. The hosted workflow is manual, requires an
exact `main` commit and protected-environment approval, and stops at an
unpublished GitHub draft. See
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md). It intentionally does
not include placeholder licensing or automatic-update services; those require a
real commercial provider, HTTPS download host, Sparkle appcast, and update key.

Create a stored notarization profile, then run the release workflow from a clean
candidate commit with `EASPLIT_NOTARY_PROFILE=<profile>
EASPLIT_RELEASE_LABEL=<version-label> ./script/release.sh`. The release directory
contains the exact commit, tool versions, checksums, and Apple notarization IDs
in `release-manifest.json`.

After the one-time encrypted-secret setup, the safer hosted path is **Actions →
Prepare eaSplit draft release → Run workflow**. The workflow cannot run on a
schedule or source change, does not push a tag, and does not publish a release.
The exact draft bytes still require clean-Mac acceptance and an intentional
human publish action.

The private-beta landing, install, privacy, support, terms, and download surface
is in [`site/`](site/). The clean-Mac acceptance procedure is in
[`docs/BETA_ACCEPTANCE.md`](docs/BETA_ACCEPTANCE.md).

## Privacy boundary

Window titles are used only to distinguish visible choices in the picker. They
are not logged, transmitted, or persisted in saved recipes. eaSplit has no
analytics or account system.

## Open-source notices

The global-shortcut recorder uses KeyboardShortcuts 3.0.1. Its MIT license is
included in the application bundle and in
`eaSplit/Resources/ThirdPartyNotices.txt`.
