#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=tests/fixture.sh
source "$ROOT/tests/fixture.sh"
ZVM="$ROOT/zvm"
DRIVER="${ZVM_TEST_BASH:-/bin/bash}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/zvm.test.XXXXXXXX")
child=''
trap 'if [[ -n "$child" ]]; then kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; fi; rm -rf -- "$tmp"' EXIT
fixture "$tmp/work space"
cd "$HOME"
run() { "$DRIVER" "$ZVM" "$@"; }
bad() {
    local message="$1"; shift
    if run "$@" < /dev/null > "$tmp/out" 2> "$tmp/err"; then fail_test "unexpected success: $*"; fi
    [[ -z "$message" ]] || grep -F -- "$message" "$tmp/err" || fail_test "missing diagnostic ($*): $message"
}
selected() { [[ "$(run current)" == "$1" ]] || fail_test "expected selection $1"; }

# Help/current/local list do not check dependencies, create files, or clean up.
mkdir "$tmp/empty-path"
PATH="$tmp/empty-path" run --help > "$tmp/help"
grep -F 'zvm install --use latest' "$tmp/help"
PATH="$tmp/empty-path" run --version > "$tmp/version"
bad '' current
[[ ! -s "$tmp/out" ]]
# Check an actual missing dependency without relying on the runner's installed tools.
if PATH="$tmp/empty-path" run install "$A" --no-zls > "$tmp/out" 2> "$tmp/err"; then fail_test 'missing flock'; fi
grep -F 'Missing required tool: flock' "$tmp/err"
[[ ! -e "$DATA" && ! -e "$CACHE" ]]
bad 'Usage' install
bad 'Unknown command' help
bad 'Unexpected' --version extra
bad 'Invalid' install abc123
bad 'Invalid' install ../escape
bad 'Expected one' install "$A" "$B"
bad 'Usage' list --force
bad 'Expected a concrete' use ../escape
bad 'Expected a concrete' uninstall ../escape
# shellcheck disable=SC2016 # Literal malicious-looking project data.
printf '%s\n' '$(touch SHAME)' > .zvmrc
bad 'Invalid install spec' install
[[ ! -e SHAME && ! -e "$DATA" ]]

# Install, offline selection with no download tools, exact override and switch.
printf '# Pin\n  %s  \n' "$A" > .zvmrc
run install --no-zls
bad '' current
[[ ! -e "$TEST_BIN/zig" && -x "$VERSIONS/$A/zig" && -f "$VERSIONS/$A/lib/std.zig" ]]
cp "$FIXTURE/requests" "$tmp/requests"
touch "$FIXTURE/offline"
isolated_path "$tmp/local-path" flock mkdir mktemp ln mv readlink rm uname cmp tr
PATH="$tmp/local-path" run use
cmp "$tmp/requests" "$FIXTURE/requests"
selected "$A"
bad "zvm install --use $B" use "$B"
rm "$FIXTURE/offline"
run install "$B" --no-zls
[[ "$(grep -c '/index.json' "$FIXTURE/requests")" == 1 ]]
selected "$A"
[[ -d "$DATA/current" ]]
run use "$B"
selected "$B"
[[ "$(readlink "$DATA/current")" == "versions/$B" && ! -e "$VERSIONS/$A/current" ]]
[[ "$("$TEST_BIN/zig" version)" == "$B" ]]
bad 'unset' uninstall "$B"
run list | grep -Fx "* $B"
run unset
[[ ! -L "$TEST_BIN/zig" && ! -L "$DATA/current" ]]
run uninstall "$B"
[[ ! -e "$VERSIONS/$B" && -d "$VERSIONS/$A" ]]
run install latest --no-zls
[[ -d "$VERSIONS/$C" && ! -e "$VERSIONS/99.9.9" ]]
[[ "$(grep -c '/index.json' "$FIXTURE/requests")" == 1 ]]
run install "$DEV" --use
selected "$DEV"
grep -F 'zig_version=0.11.0-dev.12%2Babc123&compatibility=full' "$FIXTURE/requests"
run list --remote | grep -Fx "dev $DEV"

# Optional ZLS vs transport, metadata, or checksum failure.
run use "$A"
bad 'not available' zls install
run install "$A" 2> "$tmp/err"
grep -F 'not available' "$tmp/err"
[[ ! -L "$TEST_BIN/zls" ]]
mv "$FIXTURE/zls.json" "$tmp/unsupported"
bad 'Download failed' zls install
printf '%s\n' '{"code":7,"message":"server failed"}' > "$FIXTURE/zls.json"
bad 'invalid ZLS metadata' zls install
zls_archive
cp "$FIXTURE/zls.json" "$tmp/good-zls"
jq --arg p "$TARGET" '.[$p].shasum = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
    "$tmp/good-zls" > "$FIXTURE/zls.json"
bad 'Checksum mismatch' install "$B" --use
selected "$A"
[[ ! -e "$VERSIONS/$B" ]]
cp "$tmp/good-zls" "$FIXTURE/zls.json"
run zls install
[[ -x "$TEST_BIN/zls" ]]
cp "$FIXTURE/requests" "$tmp/requests"
run zls install
run install "$A" --no-zls
cmp "$tmp/requests" "$FIXTURE/requests"
[[ -x "$TEST_BIN/zls" ]]
run use "$C"
[[ ! -e "$TEST_BIN/zls" ]]
rm "$TEST_BIN/zls"
ln -s foreign "$TEST_BIN/zls"
bad 'Refusing' use "$A"
selected "$C"
[[ "$(readlink "$TEST_BIN/zls")" == foreign ]]
rm "$TEST_BIN/zls"
# Fail the commit itself after it has created a new ZLS link; roll that back.
export REAL_MV; REAL_MV=$(command -v mv)
cat > "$FIXTURE/mv" <<'BASH'
#!/bin/bash
case "${!#}" in */current) exit 71 ;; esac
exec "$REAL_MV" "$@"
BASH
chmod +x "$FIXTURE/mv"
bad 'Cannot select' use "$A"
selected "$C"
[[ ! -L "$TEST_BIN/zls" && "$("$TEST_BIN/zig" version)" == "$C" ]]
rm "$FIXTURE/mv"
run use "$A"

# Cache corruption, invalid remote input, archives with unsafe member paths/types.
archive="$CACHE/downloads/$(digest "$FIXTURE/$A.tar.xz").tar.xz"
printf corrupt > "$archive"
run use "$C"
run uninstall "$A"
run install "$A" --no-zls
cmp "$archive" "$FIXTURE/$A.tar.xz"
cp "$CACHE/index.json" "$tmp/last-good"
touch -t 200001010000 "$CACHE/index.json"
cp "$FIXTURE/index.json" "$tmp/good-index"
jq --arg p "$TARGET" --arg v "$B" '.[$v][$p].shasum = "none"' "$tmp/good-index" > "$FIXTURE/index.json"
bad 'Invalid Zig index' list --remote
cmp "$tmp/last-good" "$CACHE/index.json"
cp "$FIXTURE/$B.tar.xz" "$tmp/good-b.tar.xz"
for kind in traversal symlink hardlink newline layout; do
    zig_archive "$B"
    src="$FIXTURE/zig-src"
    case "$kind" in
        traversal) bsdtar --format=ustar -cJf "$FIXTURE/$B.tar.xz" -s '|^dist|../dist|' -C "$src" dist ;;
        symlink) ln -s ../../foreign "$src/dist/bad" ;;
        hardlink) ln "$src/dist/zig" "$src/dist/bad" ;;
        newline) touch "$src/dist/"$'bad\nname' ;;
        layout) rm "$src/dist/zig" ;;
    esac
    if [[ "$kind" != traversal ]]; then
        bsdtar --format=ustar -cJf "$FIXTURE/$B.tar.xz" -C "$src" dist
        rm -f "$src/dist/bad" "$src/dist/"$'bad\nname'
    fi
    jq --arg p "$TARGET" --arg v "$B" --arg hash "$(digest "$FIXTURE/$B.tar.xz")" \
        '.[$v][$p].shasum = $hash' "$tmp/good-index" > "$FIXTURE/index.json"
    touch -t 200001010000 "$CACHE/index.json"
    if [[ "$kind" == layout ]]; then bad 'distribution layout' install "$B" --no-zls
    else bad 'Unsafe archive' install "$B" --no-zls; fi
    [[ ! -e "$VERSIONS/$B" && ! -e "$DATA/dist" ]]
done
cp "$tmp/good-b.tar.xz" "$FIXTURE/$B.tar.xz"
cp "$tmp/good-index" "$FIXTURE/index.json"
touch -t 200001010000 "$CACHE/index.json"
bad '' uninstall "$B"

# Paused install leaves readers alone and excludes other mutators; TERM only
# the manager PID so this also checks transfer cancellation and lock release.
rm -- "$CACHE/downloads/$(digest "$FIXTURE/$B.tar.xz").tar.xz"
touch "$FIXTURE/pause"
"$DRIVER" "$ZVM" install "$B" --no-zls --use > "$tmp/install.out" 2> "$tmp/install.err" &
child=$!
reaches "$FIXTURE/paused" "$child" || { printf '%s\n' 'Install never paused' >&2; grep . "$tmp/install.err" >&2; exit 1; }
run --help > /dev/null
run list > /dev/null
bad 'lock' unset
bad 'lock' install "$A" --no-zls
# A different data root still contends on the same archive cache. It may
# read the fresh index, but can't stage a second download or disturb ours.
cp "$FIXTURE/requests" "$tmp/paused-requests"
XDG_DATA_HOME="$tmp/independent-data" run list --remote > /dev/null
XDG_DATA_HOME="$tmp/independent-data" bad 'cache lock' install "$B" --no-zls
cmp "$tmp/paused-requests" "$FIXTURE/requests"
[[ ! -e "$tmp/independent-data/zvm/versions/$B" ]]
[[ -n "$(find "$CACHE" -name archive.part)" ]]
selected "$C"
kill -TERM "$child"
if wait "$child"; then fail_test 'interrupted install succeeded'; fi
child=''
rm "$FIXTURE/pause"
[[ ! -e "$VERSIONS/$B" && -z "$(find "$DATA" "$CACHE" -name '*.part' -o -name '.stage.*')" ]]
selected "$C"

# Terminate during extraction after verified bytes are on disk. The private
# stage may contain partial files, but the toolchain must never be published.
export REAL_BSDTAR; REAL_BSDTAR=$(command -v bsdtar)
cat > "$FIXTURE/bsdtar" <<'BASH'
#!/bin/bash
if [[ "$1" == --safe-writes ]]; then
    printf partial > "${!#}/partial"
    touch "$FIXTURE/extracting"
    while [[ ! -e "$FIXTURE/stop-extracting" ]]; do sleep .05; done
fi
exec "$REAL_BSDTAR" "$@"
BASH
chmod +x "$FIXTURE/bsdtar"
"$DRIVER" "$ZVM" install "$B" --no-zls --use > "$tmp/install.out" 2> "$tmp/install.err" &
child=$!
reaches "$FIXTURE/extracting" "$child" || fail_test 'extraction did not pause'
kill -TERM "$child"
if wait "$child"; then fail_test 'interrupted extraction succeeded'; fi
child=''
[[ ! -e "$VERSIONS/$B" && -z "$(find "$DATA" "$CACHE" -name '.stage.*')" ]]
selected "$C"
rm "$FIXTURE/bsdtar"
cp "$FIXTURE/requests" "$tmp/requests"
XDG_DATA_HOME="$tmp/independent-data" run install "$B" --no-zls
[[ -x "$tmp/independent-data/zvm/versions/$B/zig" ]]
run install "$B" --no-zls
cmp "$tmp/requests" "$FIXTURE/requests"

# Cancellation and confirmed removal, including bundled ZLS and active Zig.
run zls install "$B"
run use "$B"
mkdir -p "$VERSIONS/1.2.3" "$XDG_CONFIG_HOME/zvm"
touch "$VERSIONS/1.2.3/foreign" "$XDG_CONFIG_HOME/zvm/config" "$TEST_BIN/zvm"
ln -s "$VERSIONS/1.2.3" "$VERSIONS/9.9.9"
rm "$TEST_BIN/zig"
printf foreign > "$TEST_BIN/zig"
bad 'Refusing' use "$C"
selected "$B"
bad 'Usage' uninstall "$A" --all
snapshot "$tmp/work space" > "$tmp/before"
bad '--yes' uninstall --all
export ZVM_PATH="$ZVM" ZVM_TEST_BASH="$DRIVER"
expect <<'TCL'
set timeout 10
spawn -noecho $env(ZVM_TEST_BASH) $env(ZVM_PATH) uninstall --all
expect {
    -exact {installations? [y/N]} { send -- "n\r" }
    timeout { exit 1 }
    eof { exit 1 }
}
expect {
    -exact {Cancelled.} {}
    timeout { exit 1 }
    eof { exit 1 }
}
expect eof
exit [lindex [wait] 3]
TCL
snapshot "$tmp/work space" > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
run uninstall --all --yes
run uninstall --all
bad '' current
[[ "$(<"$TEST_BIN/zig")" == foreign && ! -L "$TEST_BIN/zls" ]]
[[ -f "$VERSIONS/1.2.3/foreign" && -L "$VERSIONS/9.9.9" && -f "$CACHE/index.json" &&
   -f .zvmrc && -f "$TEST_BIN/zvm" && -f "$XDG_CONFIG_HOME/zvm/config" && ! -e "$VERSIONS/$B" ]]
# A smuggled newline in a link target must not be treated as our exact target.
ln -s "$DATA/current/zig"$'\n' "$TEST_BIN/zls"
run unset
[[ -L "$TEST_BIN/zls" ]]
ln -s "versions/$A"$'\n' "$DATA/current"
bad 'Unrecognized' current
bad 'Refusing' unset
[[ -L "$DATA/current" ]]
printf 'Acceptance checks passed (%s)\n' "$("$DRIVER" --version | head -1)"
