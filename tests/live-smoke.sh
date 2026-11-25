#!/usr/bin/env bash
set -euo pipefail
# Keep this pair pinned on both primary CI platforms. Update together if the
# upstream selector changes its compatible release for this Zig version.
readonly expected_zig=0.15.2 expected_zls=0.15.1
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
export PATH="$HOME/.local/bin:$PATH"
mkdir "$HOME"
/bin/bash "$root/zvm" list --remote > "$tmp/remote"
grep -Fx "stable $expected_zig" "$tmp/remote"
/bin/bash "$root/zvm" install "$expected_zig" --use
[[ "$(/bin/bash "$root/zvm" current)" == "$expected_zig" ]]
for tool in zig zls; do
    [[ -L "$HOME/.local/bin/$tool" && -x "$HOME/.local/bin/$tool" ]] || {
        printf 'Missing selected executable: %s\n' "$tool" >&2
        exit 1
    }
done
zig_actual=$("$HOME/.local/bin/zig" version)
zls_actual=$("$HOME/.local/bin/zls" --version)
if [[ "$zig_actual" != "$expected_zig" || "$zls_actual" != "$expected_zls" ]]; then
    printf 'Expected Zig %s and ZLS %s; got Zig %s and ZLS %s\n' \
        "$expected_zig" "$expected_zls" "$zig_actual" "$zls_actual" >&2
    exit 1
fi
/bin/bash "$root/zvm" uninstall --all --yes
[[ ! -L "$HOME/.local/bin/zig" && ! -L "$HOME/.local/bin/zls" ]]
printf 'Upstream Zig %s and ZLS %s passed.\n' "$zig_actual" "$zls_actual"
