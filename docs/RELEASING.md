# Releases

[简体中文](RELEASING.zh-CN.md) · [Back to OnTop](../README.md)

## One-command release

After committing your work on `main`, run:

```bash
make release                   # 1.3.0 → 1.3.1
make release VERSION=1.4.0      # Or choose a newer version
```

Choose one command. It increments the app version and build number, adds a changelog entry, creates bilingual release notes from commits since the current version tag, commits those changes, creates an annotated tag, and **atomically pushes main and the tag**. GitHub Actions tests, builds, uploads the DMG/ZIP/checksums, attests their provenance, and publishes the release. You do not need to build or upload installers locally.

The command requires Python 3.9+, Git, Make, a clean working tree on `main`, and push access to `origin`. It fetches remote changes and rejects an outdated/diverged branch, an existing tag, or a non-increasing version. Committed local work ahead of `origin/main` is included in the push. No force push is used.

For curated notes, commit `docs/releases/v<next-version>.md` and a matching `CHANGELOG.md` entry before running the command; your text is preserved. Otherwise the generated notes include original commit titles and English/Chinese installation instructions. Keep user documentation in sync and complete the [manual acceptance checks](DEVELOPMENT.md#manual-acceptance) when changing app behavior.

The command returns when the push succeeds; the release appears **after CI passes**. Follow its printed workflow link. If a push fails, the commit and tag remain locally and the command prints the exact `git push --atomic …` command to retry. Do not bump again just to retry a failed push.

To publish a version already prepared and committed by hand (including the initial release), push `main` and run `./scripts/tag-release.sh`. This lower-level command does not bump or commit anything.

## What CD does

The [Release workflow](../.github/workflows/release.yml) checks that the tag matches the app version, changelog, and release notes. It then calls the same [CI workflow](../.github/workflows/ci.yml) used for pull requests:

1. Lint scripts/workflows, check documentation links/translations/metadata, and test release automation against disposable Git repositories and a fake GitHub CLI.
2. Run native tests in both languages on Apple Silicon and Intel.
3. Build universal installers and verify code signatures, architectures, license/resources, checksums, and ZIP/DMG round trips.
4. Download the verified Apple Silicon job's universal artifacts and verify their hashes again.
5. Create GitHub build-provenance attestations for the DMG and ZIP.
6. Upload assets to a draft, then publish with the version's English/Chinese notes.

The publish job has narrowly scoped write/OIDC permissions. PR tests are read-only and do not use release credentials. Actions are pinned to commit SHAs; Dependabot opens grouped updates.

If an upload is interrupted, rerun the failed job: an existing draft can be completed. A published release is never overwritten. For a fix after publication, use a new version. Do not move a published tag.

## Local packaging

```bash
./scripts/package.sh
./scripts/test-package.sh
```

`dist/` contains `OnTop.app`, a universal DMG and ZIP, and `SHA256SUMS`. Build/package failures preserve the previous successful distribution. Generated installers are release assets, not source commits.

## Verifying a download

Download the installer and `SHA256SUMS` from the same release. To verify one downloaded file:

```bash
shasum -a 256 OnTop-1.3.0-universal.dmg
# Compare the digest with its entry in SHA256SUMS.
```

If you downloaded both DMG and ZIP, run `shasum -a 256 -c SHA256SUMS` from that directory.

With the GitHub CLI installed, also verify where the installer was built:

```bash
gh attestation verify OnTop-1.3.0-universal.dmg --repo laixintao/ontop
```

[GitHub's attestation documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-artifact-attestations) describes the verification model.

## Signing status

Current builds use an **ad-hoc signature** and are **not Apple-notarized**. GitHub provenance verifies workflow origin; it does not satisfy Gatekeeper's Developer ID/notarization requirements. Installation instructions disclose the first-launch behavior.

A future notarized distribution requires an Apple Developer account, Developer ID signing identity, and notarization credentials. These are not bundled, guessed, or required for this release pipeline. Do not disable Gatekeeper to install OnTop.
