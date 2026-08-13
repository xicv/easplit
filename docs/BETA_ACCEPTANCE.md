# eaSplit private-beta acceptance

This is the final gate before giving the beta link to testers. Run it on a Mac
that has never had an eaSplit development build or signing certificate.

## Release bytes

- Candidate: `eaSplit-0.1.0-beta.4.dmg`
- Product version: `0.1.0`
- Build: `4`
- Minimum system: macOS 15
- Architectures: Apple silicon and Intel

Use only the DMG and adjacent SHA-256 file published from the same qualified
release directory. Do not rebuild, rename, re-sign, or recompress the artifact
after recording its checksum.

## Clean-Mac install

1. Download the DMG through the actual hosted beta page.
2. Compare `shasum -a 256 eaSplit-0.1.0-beta.4.dmg` with the published checksum.
3. Open the DMG in Finder without bypassing any Gatekeeper warning.
4. Confirm the image contains `eaSplit.app` and an `Applications` shortcut.
5. Drag eaSplit to Applications, eject the image, and launch the installed copy.
6. Confirm no “unidentified developer” or “damaged” warning appears.
7. Confirm eaSplit appears only in the menu bar and its icon is crisp in Finder,
   the Accessibility list, and the menu bar.

Record the Mac model, architecture, macOS version, download checksum, and the
exact result of each step. Repeat on at least one Apple silicon Mac and one Intel
Mac before calling the beta generally available.

## Permission and core workflow

For a repeatable local window set, run `./script/run_acceptance_fixture.sh`.
The picker should include **Browser Fixture** and **Chat Fixture** as separate
windows. It should exclude **Fixed Panel — should not appear**. The fixture is a
separate development target and is never embedded in the release app or DMG.

Before the manual checks, run `./script/run_acceptance_matrix.sh`. It uses the
signed development app to exercise the two fixture windows through the real
Accessibility API, including the frequent-suggestion flow, all two-window
layout/ratio/gap combinations, slot-1 keyboard focus, and undo. Its
machine-readable result is written to `.build/acceptance/report.json`. This
debug-only gate does not write to the production recipe or suggestion stores.

1. Select **Request Access** and enable the production **eaSplit** entry in
   System Settings → Privacy & Security → Accessibility.
2. Return to eaSplit. Approval should be detected automatically; use
   **Check Again** once if needed.
3. Open two normal, resizable application windows.
4. Verify refresh, recent-window ordering, window selection, and slot numbering.
5. Exercise columns and rows at every available ratio with a visible gap.
6. Enable **Fill screen edge to edge** and verify zero screen-edge and center gap.
7. Leave **Bring split windows forward** enabled, cover both selected windows
   with an unrelated window, and split. Verify both selected windows are visible
   above the unrelated window and slot 1 receives keyboard focus. Then replace
   slot 2 with a third application and split again; the old slot-2 application
   must remain behind both newly selected windows.
8. Disable **Bring split windows forward** and repeat. Verify geometry still
   changes without eaSplit explicitly raising or focusing either window.
9. Exercise three columns and focus-plus-stack with three windows.
10. Verify a saved recipe, repeat last split, undo, and deletion.
11. Assign and exercise each global shortcut, including after quitting and
    reopening eaSplit.
12. Enable and disable launch at login, then verify the approved state after a
    real logout/login cycle.
13. While another app is active, open eaSplit from the menu bar and select
    **Settings**. Verify the Settings window is active immediately, its controls
    use the active appearance, and no second picker window opens.

## Edge matrix

Run representative checks for:

- a minimized window;
- a fixed-size or non-resizable panel;
- two windows owned by the same application;
- an application that enforces a minimum size;
- two displays with different scaling;
- a window on another Space;
- a full-screen application;
- an application that is temporarily unresponsive.

The expected behavior is a clear exclusion or failure message, not a hang,
silent partial layout, or movement of an unselected window.

## Website and support

Run `./script/beta_site_health.sh` first. It verifies the public pages, internal
references, release links, hosted DMG checksum, and release manifest. A passing
automated check does not replace the clean-Mac or window-management checks above.

1. Verify every navigation and footer link on desktop and mobile widths.
2. Download the candidate from every download button and compare the bytes.
3. Follow the public install instructions literally; correct any step that
   relies on developer knowledge.
4. Confirm the privacy page matches the shipping binary and no network request
   is made by the app.
5. Send one harmless test report through the public beta feedback form. Confirm
   it receives the `beta-feedback` label, appears in the filtered Issues inbox,
   and reaches the developer's GitHub notification stream; then close it.

## Tester feedback template

Ask testers to return:

- Mac model, chip, and macOS version;
- eaSplit version and build;
- applications and layout involved;
- what they expected and what happened;
- exact error text, if any;
- whether they would reuse the saved combination next week;
- whether the product would be worth a one-time purchase, and why.

Do not ask testers to send private documents or sensitive window titles.

## Release decision

The beta is ready to invite users only when there are no unresolved install,
Gatekeeper, Accessibility, crash, data-loss, or wrong-window failures. Cosmetic
issues may be recorded for the next build if they do not hide controls, break
keyboard access, or misrepresent the product.
