# Release checklist

eaSplit's production lane is direct distribution. A Mac App Store build is not
a supported release target because App Sandbox prevents the cross-application
Accessibility control that defines the product.

## One-time setup

- Sign in to team `6UVB8NWW6F` in Xcode and install a local
  **Developer ID Application** identity. Xcode may use a cloud-managed identity
  to export the app, but the local identity is also required to sign the DMG.
- Create an App Store Connect API key or app-specific-password credential for
  notarization, then store it with `xcrun notarytool store-credentials`.
- For the hosted draft workflow, configure the protected GitHub environment
  named `release-candidate`. Export only the **Developer ID Application**
  identity and private key to a password-protected `.p12`, and obtain an App
  Store Connect API `.p8` key that is authorized for notarization. Never add
  either file to this repository.
- Upload those credentials as encrypted environment secrets with the guarded
  helper. It requires an explicit confirmation value and prompts for the P12
  password without writing it to disk:

  ```sh
  EASPLIT_CONFIRM_SECRET_UPLOAD=release-candidate \
    ./script/configure_release_secrets.sh \
      /absolute/path/to/developer-id.p12 \
      /absolute/path/to/AuthKey_KEYID.p8 \
      APP_STORE_CONNECT_KEY_ID \
      APP_STORE_CONNECT_ISSUER_UUID
  ```

  Confirm all five environment-secret names exist in GitHub, then securely
  remove the temporary exports. Base64 is transport encoding, not encryption;
  protection comes from GitHub's encrypted-secret storage and the protected
  environment approval gate.
- Publish real support, privacy, terms, and download pages on a controlled HTTPS
  domain.
- Choose the paid-release provider and create the real product before adding
  licensing code. The current hypothesis is a one-time purchase around USD
  $12–15; Lemon Squeezy is the simplest researched license-key option.
- Before adding automatic updates, create a real Sparkle EdDSA key and hosted
  appcast. Do not ship a placeholder feed URL or private update key.

## Candidate qualification

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `./script/quality.sh`; it is the same test, coverage, lint, generated
   project, and static-analysis gate used by hosted CI.
3. Exercise Accessibility permission, selection, every layout, ratios, gaps,
   default-on foreground raising, its opt-out, recipes, repeat, undo, shortcuts,
   settings, and launch-at-login approval on a fresh standard macOS user account.
4. Exercise movable, minimized, fixed-size, multi-window, multi-display, and
   Spaces/full-screen edge cases with representative third-party applications.
5. Set the stored notarization profile and build the artifact:

   ```sh
   EASPLIT_NOTARY_PROFILE=eaSplit-notary \
     EASPLIT_RELEASE_LABEL=0.1.0-beta.4 \
     ./script/release.sh
   ```

6. Verify the generated SHA-256 checksum on a second Mac that does not have the
   development certificate, launch the app through Finder, grant Accessibility
   access, and repeat the smoke matrix.
7. Open the DMG, drag eaSplit to Applications, and verify the installed app is
   the same version and build as the qualified export.
8. Scan the DMG with the chosen malware service, upload the exact qualified
   bytes, and retain `release-manifest.json`, both app and DMG notarization
   records, and checksums with the release record.

`release.sh` fails closed unless the app is universal, Developer ID signed,
Hardened Runtime enabled, free of development and sandbox entitlements,
notarization-stapled, and accepted by Gatekeeper. The generated DMG also fails
closed unless its outer image is Developer ID signed, notarized, stapled, and
accepted by Gatekeeper. It finishes by running `script/verify_release.sh`, which
rechecks both checksums, both notarization records, the ZIP, DMG signature and
ticket, mounted app signature and ticket, architectures, version, and build.
The publication script runs the same verifier again before creating a tag or
GitHub release.

## Guarded hosted draft

The preferred candidate path automates the expensive, deterministic work while
leaving publication as a separate human decision:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   A beta label `X.Y.Z-beta.N` must match both values: `X.Y.Z` is the marketing
   version and `N` is the build number.
2. Add complete release notes at `docs/releases/X.Y.Z-beta.N.md`; `TODO`, `TBD`,
   and placeholder notes fail the preflight.
3. Run `./script/quality.sh`, commit the coherent candidate, push it to `main`,
   and wait for the hosted `quality` check to pass on that exact SHA.
4. Open **Actions → Prepare eaSplit draft release → Run workflow**. Enter the
   release label and full 40-character `main` SHA, select the confirmation, and
   run it from `main`.
5. Review the read-only preflight, then approve the protected
   `release-candidate` environment. The macOS job imports credentials into an
   isolated temporary keychain, performs both Apple notarizations, verifies the
   mounted DMG, and creates a prerelease draft containing only the DMG,
   checksum, and manifest.
6. Download the exact draft DMG while signed in, run the clean-Mac procedure in
   `docs/BETA_ACCEPTANCE.md`, and inspect the retained manifest and both
   notarization logs.
7. If every human gate passes, open the draft in GitHub and publish it manually.
   If a gate fails, delete the draft, fix the issue in a new build, and create a
   new candidate. Never replace qualified bytes under the same version.
8. Update the website to the newly published version, push that site-only
   change, and confirm the Pages deployment and beta-health checks pass.

The workflow has no `push` or schedule trigger, cannot draft from a stale or
non-`main` SHA, does not push a tag, and uses `gh release create --draft`. GitHub
withholds its environment secrets until the approval gate. The temporary
keychain and decoded credentials are removed even when the job fails. Compact
release evidence is retained for 30 days; it does not contain private keys.

The local `release.sh` lane remains available for diagnosis or a controlled
fallback. `publish_github_release.sh` publishes immediately and should only be
used after the same acceptance gates; it is not called by the hosted workflow.
