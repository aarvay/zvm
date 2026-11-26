# Releasing zvm

**Start here:** tell your agent, “Guide me through a signed zvm release using `docs/RELEASE.md`. Start with read-only preflight.” For everyday development, fixture tests and platform coverage, see [AGENTS.md](../AGENTS.md).

**Agent contract:** inspect the actual repo and workflows first. Report the proposed tag, exact commit, destination and any blockers. Run local checks yourself; stop on any failure. Ask the maintainer to confirm the exact tag/commit before signing or pushing, and **separately** confirm before publishing the verified draft. Never ask for private key material or a passphrase in chat: the maintainer signs locally using GPG pinentry. Use the configured SSH remotes for Git. Tell the maintainer before Git or signing operations that may require a YubiKey touch; if authentication fails, stop and ask rather than switching to HTTPS or changing credentials. Do not change account settings, force-push, overwrite assets, or publish the tap without approval. If resuming, inspect remote state instead of repeating commands blindly.

## 0. One-time setup — required before pushing a release tag

- Confirm `origin` is the intended `aarvay/zvm` repository, GitHub CLI is authenticated (`gh auth status`), and the maintainer can create releases. Configure protected version tags, a protected `release` environment and immutable releases where available. The companion tap is `aarvay/homebrew-tap` (locally `../homebrew-tap`).
- List signing keys locally: `gpg --list-secret-keys --fingerprint`. Confirm the full **primary-key fingerprint** independently and set it as the uppercase repository Actions variable `RELEASE_GPG_FINGERPRINT` before pushing any release tag. Upload only the public key (including the signing subkey) to the `aarvay` GitHub account so it is served at <https://github.com/aarvay.gpg>. Do not commit a key or fingerprint file. Share the confirmed fingerprint through a trusted channel so users can authenticate the downloaded key. Keep all private key material off CI.
- **Workflow prerequisite:** inspect [release.yml](../.github/workflows/release.yml) at the *release commit*, not just the working tree. The workflow fetches the annotated tag and `https://github.com/aarvay.gpg`, imports only the key matching `RELEASE_GPG_FINGERPRINT` into a clean verification keyring, and verifies the tag with `git verify-tag`. An unset or invalid pin, failed fetch, missing key, or invalid signature must stop the workflow before fixture CI and live smoke. The release job builds and attests the exact tag and stops after verifying the uploaded **draft**. `gh release create --verify-tag` checks remote existence, not the GPG signature.

## 1. Preflight and sign the tag

### YubiKey preflight (each release)

In your local terminal, insert the YubiKey and run `gpg --card-status` and `gpg --list-secret-keys --with-subkey-fingerprint`. Match the card’s **Signature key** fingerprint to the signing-capable (`[S]`) subkey under the trusted primary key. `ssb>` indicates a card-backed subkey. Stop if the fingerprints do not match; do not fall back to another key.

```bash
FPR='FULL_PRIMARY_KEY_FINGERPRINT'          # Identity pinned by CI and users
SIGNER='FULL_SIGNING_SUBKEY_FINGERPRINT!'   # Replace fingerprint; keep the quoted !
```

The trailing `!` tells GPG to use that exact subkey. CI and users need only the exported **public** key (including its public signing subkey), not the device. Have the YubiKey available twice: to sign the tag now and the draft manifest later. Enter the PIN only in local pinentry and touch the key if prompted. If the agent cannot display pinentry, run the signing commands yourself in your terminal; for terminal pinentry, first run `export GPG_TTY="$(tty)"`. Never share the PIN in chat or put it or the private key in GitHub secrets.

### Tag preflight

Run from the zvm repo in Bash. Derive the tag; don’t guess it:

```bash
REPO=aarvay/zvm
TAG="v$(./zvm --version)"
COMMIT=$(git rev-parse HEAD)
git status --short --branch
git remote get-url origin
git ls-remote --tags origin "refs/tags/$TAG"
```

Require a clean, reviewed commit on the intended remote branch, a stable `vX.Y.Z` matching the intended version, no conflicting local/remote tag or release, green fixture CI and reviewed release notes. For a new version, update `VERSION` in `zvm` **before** freezing the commit. If there is no commit/remote yet, stop; do not initialize or publish on the maintainer’s behalf. Check the test commands in `AGENTS.md` when making release changes.

After approval, the maintainer signs the tag locally; push only that tag:

```bash
git -c gpg.format=openpgp tag -s -u "$SIGNER" -m "Release $TAG" "$TAG" "$COMMIT"
git -c gpg.format=openpgp verify-tag "$TAG"
test "$(git rev-parse "$TAG^{commit}")" = "$COMMIT" && git push origin "refs/tags/$TAG"
```

Watch the **Release** Actions run for this tag/commit (`gh run list --repo "$REPO" --workflow release.yml`, then `gh run watch RUN_ID --repo "$REPO" --exit-status`). Require both deterministic CI and the pinned Linux/macOS upstream Zig+ZLS smoke to pass. The result must be a draft, not a public release.

## 2. Verify the actual draft and sign its manifest

Run the following checks as a fail-fast Bash block with `set -euo pipefail`, keeping `REPO`, `TAG`, `FPR` and `SIGNER` set in that shell. Use a fresh private directory; **never sign a local rebuild**. Stop if the workflow or tag differs from the approved one.

```bash
set -euo pipefail
test "$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft)" = true
WORK=$(mktemp -d)
gh release download "$TAG" --repo "$REPO" --dir "$WORK"
verify_manifest() {
    gh attestation verify "$1" --repo "$REPO" \
        --signer-workflow "$REPO/.github/workflows/release.yml" --source-ref "refs/tags/$TAG"
}
verify_manifest "$WORK/SHA256SUMS"
(cd "$WORK" && shasum -a 256 -c SHA256SUMS)
/bin/bash tests/installer.sh "$WORK"
```

Confirm the draft contains `zvm`, `install.sh`, `zvm-source.tar.gz` and `SHA256SUMS`, the manifest covers all three payloads, and the release notes describe the right version. The attestation identifies the producing workflow; the signature below records **your approval of its exact bytes**. With the maintainer at the local terminal:

```bash
gpg --armor --detach-sign --local-user "$SIGNER" --output "$WORK/SHA256SUMS.asc" "$WORK/SHA256SUMS"
gpg --verify "$WORK/SHA256SUMS.asc" "$WORK/SHA256SUMS"
gh release upload "$TAG" "$WORK/SHA256SUMS.asc" --repo "$REPO"
```

Before publishing, download the draft again to a **new** directory, rerun `verify_manifest` and the checksum check there, compare the downloaded signature and manifest byte-for-byte with the locally approved copies, and verify the downloaded `.asc` against the downloaded manifest with GPG. A generic “Good signature” is not identity verification: check against the pinned key. Report checks and ask for final publish approval.

## 3. Publish, verify, update Homebrew

```bash
gh release edit "$TAG" --repo "$REPO" --draft=false
gh release view "$TAG" --repo "$REPO" --json url,isDraft,tagName
```

Verify the public tag URL and asset downloads. Users who want independent verification import the authenticated public key, then run `gpg --verify SHA256SUMS.asc SHA256SUMS` and `shasum -a 256 -c SHA256SUMS` alongside the downloaded assets. The convenience curl installer does not itself authenticate a GPG signature.

From `../homebrew-tap`, run `bash scripts/update-zvm.sh "$TAG"` against the **published** assets. Review `Formula/zvm.rb`; with approval, open one tap PR and wait for **Formula CI** to pass. This job runs `brew install --build-from-source aarvay/tap/zvm` and `brew test aarvay/tap/zvm` on a clean macOS runner. The formula installs directly from the verified release bundle; no bottle build, `brew pr-pull`, or direct push to tap `main` is needed.

Merge the tap PR using GitHub's normal **Create a merge commit** option (or `gh pr merge --merge`) to preserve the reviewed commits. Confirm GitHub marks it **Merged** and the formula on `main` points to the published tag. Report the release URL, tag/commit, signing fingerprint, check results and tap PR status. Remove only the private scratch directories created for this release after verification.

## If something fails

- **Before tag push:** stop and fix preflight. **After tag push:** never move/reuse the tag for different source. A source fix gets a new version.
- **Existing draft or interrupted run:** inspect assets and Actions logs. A rerun that attempts `gh release create` again may fail because the draft exists. Resume verification only if its provenance and contents match; otherwise stop for human review. Never silently delete a draft or pass `--clobber`.
- **Already public, wrong digest, unexpected signer, or missing attestation:** stop. Don’t “fix” public bytes in place. Investigate, notify the maintainer, and issue a new signed release if needed. A failed tap update does not require republishing zvm.
