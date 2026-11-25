# Working on zvm

`zvm` is a standalone Bash 3.2+ script, with explicit command dispatch and no
build step. `refactor.md` defines the prerelease contract. Keep the
implementation in Bash with named tools, not embedded Python or Perl. Use
four-space indentation, quoted expansions, `printf`, and explicit checks for
critical operations (especially helpers invoked in conditionals). Keep stdout
for data and stderr for diagnostics. Do not add aliases, shell hooks, automatic
dependency installs or an updater.

## Architecture and invariants

- Distinguish requested specs (`latest`, `master`, concrete IDs) from validated
  concrete IDs. Never execute a `.zvmrc`. Only argument-less `install` and `use`
  read it from the working directory.
- Local mutations lock the XDG data directory inode; cache writes lock the cache
  directory inode independently. Acquire data before cache if both are needed.
  Retain the nonblocking `flock` descriptors for the operation, never unlink the
  inodes, and close descriptors for background workers. Local `list`, `current`,
  help and completion reads take neither lock. `list --remote` takes only the
  cache lock, and only when refreshing.
- Keep the one-hour validated index and content-addressed archives under the XDG
  cache. A single verified archive path serves Zig and ZLS. Never extract or
  execute an unverified download. Store `.part` files only in a private
  operation stage. Register cleanup inside execution; cleanup owns only its own
  temporaries.
- Validate member paths and types with BSD tar, then extract with the same
  reader into a private stage on the destination filesystem. Publish a complete
  Zig distribution, validate its reported version, and mark it as managed.
  Ownership is not inferred from a version-like directory name. Never delete
  unmarked, legacy or symlinked version entries.
- Selection is `current -> versions/<id>` and updates via same-filesystem
  replacement. Owned bin links have exact target strings through `current`; do
  not force-overwrite any path at `~/.local/bin/{zig,zls}`. `use` is local and
  does not require network or download dependencies. Bulk removal must confirm
  before changing selection or deleting anything.
- The private `__complete {installed|inactive|installable}` provider emits
  tab-separated IDs and optional descriptions, without writes or refreshes. Keep
  argument parsing native to Bash/Zsh/Fish; completion cannot depend on
  human-formatted list output.

## Checks

Dependencies: stock Bash 3.2+ and standard utilities; `flock`, `curl`, `jq`,
`sha256sum` or `shasum`, and BSD tar with XZ (system `tar` on macOS;
`libarchive-tools` on Ubuntu). Tests additionally use Zsh, Fish, Expect and
ShellCheck. The installer diagnoses missing packages without installing them.

```bash
for script in zvm install.sh completions/zvm-completion.bash scripts/*.sh tests/*.sh; do
    /bin/bash -n "$script" || break
done

shellcheck -x zvm install.sh completions/zvm-completion.bash scripts/*.sh tests/*.sh

/bin/bash tests/acceptance.sh
/bin/bash tests/completions.sh

work=$(mktemp -d)
/bin/bash scripts/build-release.sh aarvay/zvm "v$(/bin/bash zvm --version)" "$work/assets"
/bin/bash tests/installer.sh "$work/assets"
rm -r "$work"

/bin/bash tests/live-smoke.sh             # pinned live Zig and ZLS, isolated HOME
actionlint .github/workflows/*.yml        # if available
```

Fixture tests isolate HOME and every XDG root, stub curl, and exercise offline
activation, foreign paths, atomic symlink replacement, rollback, checksum
failures, interrupted transfers, lock contention, and bulk confirmation. Do not
test with real user toolchains. The macOS test entry point is explicitly
`/bin/bash`, not whichever Bash Homebrew puts first on PATH.

Platform verification: locally tested on Apple Silicon macOS with stock
`/bin/bash` 3.2, stock BSD tar, the `flock` implementation used by Homebrew, and
Bash/Zsh/Fish completions. CI targets `macos-15` and x86_64 `ubuntu-24.04`;
require a green run before claiming Linux release support. No claim for Intel
macOS, Linux ARM, Windows or FreeBSD without end-to-end runs.

## Release

For a release request, follow [the signed release runbook](docs/RELEASE.md), starting with read-only preflight. Do not push a tag until its workflow prerequisites are satisfied.

The checkout's `install.sh` is a template. `scripts/build-release.sh` checks the
tag against `zvm --version` and generates the tagged bootstrap, script,
source/completion bundle with license, and SHA-256 manifest. Only release builds
get the bootstrap ownership marker. Deterministic CI and the pinned live Zig/ZLS
smoke must pass on the exact tag before draft upload; verify actual draft assets
and provenance before publication. The live smoke also runs on a schedule, not
on normal PRs. Use a protected `release` environment and protected version tags;
enable immutable releases when setting up the repository. Confirm repository
ownership and license before the first release. Never publish as part of a
coding task.
