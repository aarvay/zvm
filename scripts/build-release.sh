#!/usr/bin/env bash
set -euo pipefail

[[ $# == 3 ]] || { printf 'Usage: %s OWNER/REPO vX.Y.Z NEW_OUTPUT_DIR\n' "$0" >&2; exit 1; }
repo="$1" tag="$2" out="$3"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ "$tag" == "v$("$root/zvm" --version)" ]] || { printf 'Tag does not match CLI version\n' >&2; exit 1; }
sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
mkdir -- "$out"
awk 'NR == 3 { print "# zvm GitHub release payload v1" } { print }' "$root/zvm" > "$out/zvm"
chmod 755 "$out/zvm"
sum=$(sha256 < "$out/zvm")
sed -e "s|@REPOSITORY@|$repo|g" -e "s/@TAG@/$tag/g" -e "s/@SHA256@/${sum%% *}/g" \
    "$root/install.sh" > "$out/install.sh"
chmod 755 "$out/install.sh"
tar -czf "$out/zvm-source.tar.gz" -C "$root" README.md LICENSE completions zvm
(cd -- "$out" && sha256 zvm install.sh zvm-source.tar.gz > SHA256SUMS)
