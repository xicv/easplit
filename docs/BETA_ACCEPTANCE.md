# eaSplit private-beta acceptance

This is the final gate before giving the beta link to testers. Run it on a Mac
that has never had an eaSplit development build or signing certificate.

## Release bytes

- Candidate: `eaSplit-0.1.0-beta.3.dmg`
- Product version: `0.1.0`
- Build: `3`
- Minimum system: macOS 15
- Architectures: Apple silicon and Intel

Use only the DMG and adjacent SHA-256 file published from the same qualified
release directory. Do not rebuild, rename, re-sign, or recompress the artifact
after recording its checksum.

## Clean-Mac install

1. Download the DMG through the actual hosted beta page.
2. Compare `shasum -a 256 eaSplit-0.1.0-beta.3.dmg` with the published checksum.
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

1. Select **Request Access** and enable the production **eaSplit** entry in
   System Settings → Privacy & Security → Accessibility.
2. Return to eaSplit. Approval should be detected automatically; use
   **Check Again** once if needed.
3. Open two normal, resizable application windows.
4. Verify refresh, recent-window ordering, window selection, and slot numbering.
5. Exercise columns and rows at every available ratio with a visible gap.
6. Enable **Fill screen edge to edge** and verify zero screen-edge and center gap.
7. Exercise three columns and focus-plus-stack with three windows.
8. Verify a saved recipe, repeat last split, undo, and deletion.
9. Assign and exercise each global shortcut, including after quitting and
   reopening eaSplit.
10. Enable and disable launch at login, then verify the approved state after a
    real logout/login cycle.

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

1. Verify every navigation and footer link on desktop and mobile widths.
2. Download the candidate from every download button and compare the bytes.
3. Follow the public install instructions literally; correct any step that
   relies on developer knowledge.
4. Confirm the privacy page matches the shipping binary and no network request
   is made by the app.
5. Send one issue through the invitation feedback channel and verify it reaches
   the person responsible for the beta.

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
