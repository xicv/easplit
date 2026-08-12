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
   recipes, repeat, undo, shortcuts, settings, and launch-at-login approval on
   a fresh standard macOS user account.
4. Exercise movable, minimized, fixed-size, multi-window, multi-display, and
   Spaces/full-screen edge cases with representative third-party applications.
5. Set the stored notarization profile and build the artifact:

   ```sh
   EASPLIT_NOTARY_PROFILE=eaSplit-notary \
     EASPLIT_RELEASE_LABEL=0.1.0-beta.3 \
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
accepted by Gatekeeper.
