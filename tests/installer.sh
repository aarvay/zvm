#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=tests/fixture.sh
source "$ROOT/tests/fixture.sh"
[[ $# == 1 ]] || fail_test 'provide the path to built or downloaded release assets'
assets=$(cd -- "$1" && pwd -P)
bootstrap="$assets/install.sh"
version=$(/bin/bash "$assets/zvm" --version)
tag="v$version"
sha=$(digest "$assets/zvm")
grep -Fx "readonly SHA256='$sha'" "$bootstrap"
grep -Fx "readonly TAG='$tag'" "$bootstrap"
(cd "$assets" && if command -v sha256sum >/dev/null; then sha256sum -c SHA256SUMS; else shasum -a 256 -c SHA256SUMS; fi)
bsdtar -tf "$assets/zvm-source.tar.gz" | grep -Fx LICENSE

base=$(mktemp -d)
child=''
trap 'if [[ -n "$child" ]]; then kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; fi; rm -rf -- "$base"' EXIT
export HOME="$base/home" PATH="$base/transport:$PATH" FIXTURE="$base/transport"
export XDG_DATA_HOME="$base/data" XDG_CACHE_HOME="$base/cache" XDG_STATE_HOME="$base/state" XDG_CONFIG_HOME="$base/config"
export ZVM_INSTALL_DIR="$HOME/custom bin"
mkdir -p "$HOME" "$FIXTURE" "$ZVM_INSTALL_DIR"
printf '# keep me\n' > "$HOME/.bashrc"
cat > "$FIXTURE/curl" <<'BASH'
#!/bin/bash
set -euo pipefail
out='' url=''
while (( $# )); do
    case "$1" in
        -o) out="$2"; shift ;;
        https://*) url="$1" ;;
    esac
    shift
done
[[ "$url" == https://github.com/*/releases/download/v*/zvm ]]
tag=${url%/zvm}; tag=${tag##*/}
printf '%s\n' "$out" >> "$FIXTURE/staged-paths"
if [[ -e "$FIXTURE/pause" ]]; then
    printf partial > "$out"
    touch "$FIXTURE/paused"
    while [[ -e "$FIXTURE/pause" ]]; do sleep .05; done
fi
cp "$FIXTURE/$tag" "$out"
BASH
chmod +x "$FIXTURE/curl"
cp "$assets/zvm" "$FIXTURE/$tag"
dest="$ZVM_INSTALL_DIR/zvm"
run() { /bin/bash "$1" > "$base/out" 2> "$base/err"; }
clean() {
    if [[ -d "$ZVM_INSTALL_DIR" ]]; then
        [[ -z "$(find "$ZVM_INSTALL_DIR" -name '.zvm-download.*' ! -name '.zvm-download.leftover')" ]]
    fi
}
bad() {
    if run "$1"; then fail_test "unexpected success: $2"; fi
    grep -F -- "$2" "$base/err" || fail_test "missing error: $2"
    clean
}

# Reject package/system prefixes, symlink parents, and unrelated destinations.
ZVM_INSTALL_DIR="$base" bad "$bootstrap" 'under HOME'
mkdir "$HOME/foreign"
ln -s "$HOME/foreign" "$HOME/alias"
ZVM_INSTALL_DIR="$HOME/alias/nested" bad "$bootstrap" 'Unexpected directory'
[[ ! -e "$HOME/foreign/nested" ]]
mkdir -p "$HOME/package/Cellar"
ZVM_INSTALL_DIR="$HOME/package/bin" bad "$bootstrap" 'outside package-manager prefixes'
printf '%s\n' unrelated > "$dest"
bad "$bootstrap" 'Refusing to replace unrelated path'
[[ "$(<"$dest")" == unrelated ]]
rm "$dest"
ln -s "$HOME/.bashrc" "$dest"
bad "$bootstrap" 'Refusing to replace unrelated path'
[[ -L "$dest" ]]
rm "$dest"
mkdir "$dest"
bad "$bootstrap" 'Refusing to replace unrelated path'
[[ -z "$(find "$dest" -mindepth 1)" ]]
rmdir "$dest"

# A missing bootstrap tool blocks publication; runtime-only tools do not.
isolated_path "$base/no-deps" uname
if PATH="$base/no-deps" run "$bootstrap"; then fail_test 'missing bootstrap tools'; fi
grep -F 'missing bootstrap dependencies' "$base/err"
[[ ! -e "$dest" ]]
for hasher in sha256sum shasum; do
    command -v "$hasher" >/dev/null || continue
    tools="$base/$hasher-path"
    isolated_path "$tools" "$hasher" uname flock mkdir mktemp chmod mv rm cp
    case "$(uname -s)" in
        Darwin) touch "$tools/brew"; chmod +x "$tools/brew" ;;
        Linux) touch "$tools/apt-get"; chmod +x "$tools/apt-get" ;;
    esac
    ln -s "$FIXTURE/curl" "$tools/curl"
    PATH="$tools" run "$bootstrap" || fail_test "bootstrap with $hasher: $(<"$base/err")"
    grep -F 'Missing tools: jq bsdtar' "$base/err"
    case "$(uname -s)" in
        Darwin) grep -Fx 'Install missing packages with: brew install jq libarchive' "$base/err" ;;
        Linux) grep -Fx 'Install missing packages with: sudo apt-get install jq libarchive-tools' "$base/err" ;;
    esac
    cmp "$assets/zvm" "$dest"
    clean
    rm "$dest"
done

# Old and new staging leftovers are not ours to delete or reuse. The two
# successful attempts must use distinct random paths (stock BSD mktemp).
legacy="$ZVM_INSTALL_DIR/.zvm.XXXXXXXX.part"
leftover="$ZVM_INSTALL_DIR/.zvm-download.leftover"
printf legacy > "$legacy"
printf unrelated > "$leftover"
: > "$FIXTURE/staged-paths"
run "$bootstrap" || fail_test "first install: $(<"$base/err")"
[[ -x "$dest" ]]
cmp "$assets/zvm" "$dest"
run "$bootstrap" || fail_test 'reinstall'
{
    IFS= read -r first
    IFS= read -r second
    if IFS= read -r unexpected; then fail_test "unexpected third staged path: $unexpected"; fi
} < "$FIXTURE/staged-paths"
[[ "$first" != "$second" && "${first##*/}" == .zvm-download.???????? &&
   "${second##*/}" == .zvm-download.???????? && ! -e "$first" && ! -e "$second" ]]
[[ "$(<"$legacy")" == legacy && "$(<"$leftover")" == unrelated ]]
new="$version"1
sed "s/^readonly VERSION=$version\$/readonly VERSION=$new/" "$assets/zvm" > "$FIXTURE/v$new"
new_sha=$(digest "$FIXTURE/v$new")
[[ "$new_sha" != "$sha" ]]
sed -e "s/readonly TAG='$tag'/readonly TAG='v$new'/" -e "s/$sha/$new_sha/" "$bootstrap" > "$base/update.sh"
run "$base/update.sh" || fail_test 'update'
cmp "$FIXTURE/v$new" "$dest"

# A failed publication, a completed corrupt payload and TERM during a download
# must all leave the previous installation byte-for-byte intact.
export REAL_MV; REAL_MV=$(command -v mv)
cat > "$FIXTURE/mv" <<'BASH'
#!/bin/bash
case "${!#}" in */zvm) exit 71 ;; esac
exec "$REAL_MV" "$@"
BASH
chmod +x "$FIXTURE/mv"
bad "$bootstrap" 'Cannot publish manager'
cmp "$FIXTURE/v$new" "$dest"
rm "$FIXTURE/mv"
printf corrupt > "$FIXTURE/$tag"
bad "$bootstrap" 'Checksum mismatch'
cmp "$FIXTURE/v$new" "$dest"
cp "$assets/zvm" "$FIXTURE/$tag"
touch "$FIXTURE/pause"
/bin/bash "$bootstrap" > "$base/out" 2> "$base/err" &
child=$!
reaches "$FIXTURE/paused" "$child" || fail_test 'download did not pause'
if /bin/bash "$bootstrap" > "$base/second.out" 2> "$base/second.err"; then fail_test 'competing installer succeeded'; fi
grep -F 'Cannot acquire installer lock' "$base/second.err"
kill -TERM "$child"
if wait "$child"; then fail_test 'interrupted installer succeeded'; fi
child=''
cmp "$FIXTURE/v$new" "$dest"
clean
rm "$FIXTURE/pause"
run "$bootstrap" || fail_test 'rollback'
cmp "$assets/zvm" "$dest"
[[ "$("$dest" --version)" == "$version" && "$(<"$HOME/.bashrc")" == '# keep me' ]]
[[ ! -e "$XDG_DATA_HOME" && ! -e "$XDG_CACHE_HOME" && ! -e "$XDG_CONFIG_HOME" && ! -e "$XDG_STATE_HOME" ]]
[[ "$(<"$legacy")" == legacy && "$(<"$leftover")" == unrelated ]]
printf 'Installer checks passed.\n'
