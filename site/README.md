# eaSplit beta site

This directory is a self-contained static site. It has no package installation,
build step, analytics, third-party fonts, forms, or external runtime resources.

Preview it from the repository root with:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory site
```

Then open `http://127.0.0.1:8765/`.

## Publishing gate

Before inviting testers to the GitHub Pages deployment:

1. Run `docs/BETA_ACCEPTANCE.md` against the exact DMG in its qualified release directory.
2. Publish that DMG, checksum, and manifest as one GitHub Release, then verify the hosted bytes.
3. Confirm the privacy page still describes GitHub Pages hosting and its standard
   request-data handling accurately.
4. Submit one harmless report through the public beta feedback form and confirm
   it appears in the filtered Issues inbox and developer notification stream.
5. Have the beta terms reviewed for the intended countries before a public or
   paid launch.

The operational commands, automation boundary, and feedback triage path are in
`docs/BETA_OPERATIONS.md`.

Do not add a payment link, license activation, update feed, analytics endpoint,
or support address until the corresponding real service exists and is tested.
