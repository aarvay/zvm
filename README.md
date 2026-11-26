# zvm — Zig Version Manager

Keep multiple Zig compilers installed and choose which one `zig` runs. zvm can
install a matching [Zig Language Server (ZLS)](https://github.com/zigtools/zls)
alongside each compiler, so switching Zig also switches its language server when
one is available.

I’ve used zvm for years to install and switch between Zig versions. Zig is still
pre-1.0, and a compiler update that works for one project can mean code changes
for another. I wanted to keep both versions and switch when I needed to. With
help from AI, I’ve cleaned up the tool I use myself and decided to share it now.

## Install zvm

### macOS (Homebrew)

```sh
brew install aarvay/tap/zvm
```

Homebrew installs the manager, its dependencies, and shell completions.

### Linux (Debian or Ubuntu)

```sh
sudo apt-get install curl jq libarchive-tools util-linux
```

```sh
curl -fsSL https://github.com/aarvay/zvm/releases/latest/download/install.sh | bash
```

You can also download the installer from [GitHub
Releases](https://github.com/aarvay/zvm/releases) and inspect it before running
it. It verifies the manager payload and does not edit shell profiles.

### Make the selected compiler available

On either platform, zvm links `zig` and `zls` into `~/.local/bin`, not Homebrew’s
prefix. If that directory isn’t on your PATH, for Zsh or Bash run this and add
the same line to `~/.zshrc` or `~/.bashrc` for future terminals:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

For Fish, run `fish_add_path --prepend ~/.local/bin` once instead.

## Install your first Zig toolchain

From any directory:

```sh
zvm --version              # Verify the manager is on your PATH
zvm install --use latest   # Install and select the latest stable Zig
zig version                # Verify the selected compiler
```

Without `--use`, installing a toolchain does not change your selection.

Install status goes to stderr, so stdout stays clear. On a terminal, Zig and ZLS
archive downloads show a live progress bar. Redirected logs show plain status
lines for download, verification, and extraction. Cached archives are verified
before reuse.

## Work on a project with a pinned compiler

Save one concrete Zig version in `.zvmrc` at the root of the project:

```text
0.15.2
```

From that project directory:

```sh
zvm install       # Read .zvmrc and install the toolchain without switching
zvm use           # Select the installed version; works offline
zvm current       # Print the selected version, e.g. 0.15.2
```

Selection is **per user**, not per directory or terminal. Changing directories does nothing by itself. `install` and `use` read `.zvmrc` only in the current directory and only when no version is supplied.

## Common tasks

| To… | Run |
| --- | --- |
| List installed toolchains / available builds for your platform | `zvm list` / `zvm list --remote` |
| Try a development build without changing your selection | `zvm install master` |
| Install just the compiler | `zvm install 0.15.2 --no-zls` |
| Add ZLS later for the selected compiler | `zvm zls install` |
| Switch back to an installed compiler | `zvm use 0.15.2` |
| Clear the selection but keep every installation | `zvm unset` |
| Remove an inactive toolchain and its bundled ZLS | `zvm uninstall 0.15.2` |
| Remove **all** managed toolchains, including the selected one | `zvm uninstall --all` (asks for confirmation) |

Run `zvm --help` for the full interface. [Set up tab completion for Bash, Zsh or Fish →](completions/README.md)

## Updates and removal

- **Update Zig:** `zvm install --use latest`. Older versions stay installed until you remove them.
- **Update the manager:** with Homebrew, run `brew upgrade aarvay/tap/zvm`. For a standalone install, rerun the release installer above, or use the installer from a specific release tag to pin the manager version. The repository’s `install.sh` is a release template, **not** an installer to run from `main`.
- **Remove the manager:** if you also want to remove its toolchains, run `zvm uninstall --all` first. Then run `brew uninstall aarvay/tap/zvm` for a Homebrew install, or remove `~/.local/bin/zvm` and any manually installed completions for a standalone install. Bulk uninstall leaves the download cache intact.

## Where files go

Toolchains live under `${XDG_DATA_HOME:-$HOME/.local/share}/zvm`; downloads are SHA-256 checked against upstream metadata and cached under `${XDG_CACHE_HOME:-$HOME/.cache}/zvm`. zvm exposes the selected tools through `~/.local/bin`. If `zig version` doesn’t match `zvm current`, use `command -v zig` to check which compiler your shell found. zvm won’t overwrite another tool’s executable.

**Coming from an older development checkout?** The nested toolchain layout is not migrated automatically. Back up the old data directory outside the managed root and inspect existing `zig` and `zls` links before reinstalling. Do not delete links or directories you don’t recognize.

## Development

The CLI is one Bash script (`zvm`); the fixture tests live in [`tests/`](tests/). See the [development guide](AGENTS.md) for platform requirements and test commands. Licensed under the [MIT License](LICENSE).
