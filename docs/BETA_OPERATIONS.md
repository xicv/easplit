# eaSplit beta operations

The beta has one public download, one public feedback path, and one automated
health signal. Keep those paths stable so testers never need developer-only
instructions.

## What is automated

Run the verifier locally at any time:

```sh
./script/beta_site_health.sh
```

It fetches every public page, checks internal navigation and assets, confirms
that all download buttons advertise one versioned GitHub Release DMG, downloads
the DMG, checksum, and release manifest, and verifies that the three artifacts
agree. Its own deterministic integration test is:

```sh
./script/tests/beta_site_health_test.sh
```

GitHub Actions runs the public verifier daily at 05:23 UTC and can also be run
manually from **Actions → eaSplit beta download health → Run workflow**. GitHub
Pages deployment also runs it against the newly deployed URL. GitHub may delay a
scheduled run, so use the local command when qualifying a release or responding
to a tester. GitHub disables scheduled workflows in an inactive public
repository after 60 days; re-enable the workflow before resuming a dormant beta.

Automation uses metadata mode: it checks GitHub's release-asset state, size, and
SHA-256 digest without downloading the DMG. This preserves GitHub's DMG download
counter as a useful tester-adoption signal. The local command defaults to full
mode and downloads the exact bytes for release qualification.

The automation proves public availability and byte identity. It does not prove
Gatekeeper behavior on a clean Mac, Accessibility approval, multi-display or
Spaces behavior, application-specific resizing, or sustained everyday use.
Those remain the human gates in `docs/BETA_ACCEPTANCE.md`.

## Preparing the next beta

The manual **Prepare eaSplit draft release** workflow automates the signed,
notarized, stapled, packaged, and verified candidate. It requires an exact
`main` SHA, a successful hosted quality check, explicit confirmation, and
approval for the protected `release-candidate` environment. Its final state is
an unpublished prerelease draft; it cannot change the public website or current
tester download by itself.

Follow `docs/RELEASE_CHECKLIST.md` for one-time secret setup and each release.
Only publish a draft after clean-Mac acceptance. After publishing, update the
website to point at the new immutable versioned artifact and let the Pages
deployment plus beta-health workflow prove public byte identity.

## How testers send feedback

1. Open <https://xicv.github.io/easplit/support.html>.
2. Select **Send beta feedback**.
3. Sign in to GitHub and complete the short structured form.
4. Review the privacy checkbox and submit.

The report is public. Testers must not include private documents, email
addresses, license keys, sensitive window titles, or screenshots containing
personal information.

## Where the developer sees feedback

Open the filtered inbox:

<https://github.com/xicv/easplit/issues?q=is%3Aissue+label%3Abeta-feedback>

GitHub applies the `beta-feedback` label and sends notifications according to
the repository owner's GitHub notification settings. For each report:

1. acknowledge it;
2. reproduce it against the exact reported build;
3. label any release-blocking install, crash, data-loss, or wrong-window issue;
4. link the fix and ask the tester to verify it; and
5. close it only after verification or a documented product decision.

Before inviting testers, submit one harmless test report, confirm it appears in
the filtered inbox and notification stream, then close it.

## Weekly beta report

GitHub Actions generates a read-only beta-operations report every Monday at
08:37 Australia/Adelaide time. Open:

<https://github.com/xicv/easplit/actions/workflows/beta-feedback-report.yml>

Choose the latest run and read its **Summary**. The report shows:

- feedback opened and closed during the previous seven days;
- the complete open feedback count;
- reports with no replies and reports open longer than seven days;
- stated weekly-use and one-time-purchase intent; and
- the current public website and release-metadata health result.

The report can also be generated immediately with **Run workflow**. It reads
public issues carrying the `beta-feedback` label and never comments, closes,
labels, reprioritizes, or otherwise modifies them. Issue titles are sanitized
before being written to the Actions summary; arbitrary issue-body text is not
copied into the report.
