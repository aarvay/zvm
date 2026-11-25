#!/usr/bin/env bash
# Shared fixture setup. Source from a strict-mode test, then call fixture.
fixture() {
    local root="$1" arch os
    export FIXTURE="$root/transport" HOME="$root/home" XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache"
    export XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$root/state"
    TEST_BIN="$HOME/.local/bin"
    export DATA="$XDG_DATA_HOME/zvm" CACHE="$XDG_CACHE_HOME/zvm"
    export VERSIONS="$DATA/versions"
    mkdir -p "$FIXTURE" "$TEST_BIN"
    export PATH="$FIXTURE:$TEST_BIN:$PATH"
    case "$(uname -m)" in arm64|aarch64) arch=aarch64 ;; *) arch=x86_64 ;; esac
    case "$(uname -s)" in Darwin) os=macos ;; Linux) os=linux ;; *) return 1 ;; esac
    TARGET="$arch-$os"
    A=0.9.0 B=0.10.0 C=0.10.1 DEV=0.11.0-dev.12+abc123
    cat > "$FIXTURE/curl" <<'BASH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURE/requests"
[[ ! -e "$FIXTURE/offline" ]] || exit 7
out='' url=''
while (( $# )); do
    case "$1" in
        -o) out="$2"; shift ;;
        https://*) url="$1" ;;
    esac
    shift
done
case "$url" in
    */index.json) file=index.json ;;
    */select-version\?*) file=zls.json ;;
    *) file=${url##*/} ;;
esac
if [[ -e "$FIXTURE/pause" && "$file" == *.tar.xz ]]; then
    printf partial > "$out"
    touch "$FIXTURE/paused"
    while [[ -e "$FIXTURE/pause" ]]; do sleep .05; done
fi
cp "$FIXTURE/$file" "$out"
BASH
    chmod +x "$FIXTURE/curl"
    local id
    for id in "$A" "$B" "$C" "$DEV"; do zig_archive "$id"; done
    jq -n --arg p "$TARGET" --arg a "$A" --arg b "$B" --arg c "$C" --arg dev "$DEV" \
        --arg ad "$(digest "$FIXTURE/$A.tar.xz")" --arg bd "$(digest "$FIXTURE/$B.tar.xz")" \
        --arg cd "$(digest "$FIXTURE/$C.tar.xz")" --arg dd "$(digest "$FIXTURE/$DEV.tar.xz")" '
        def build($id; $digest): {($p): {tarball: ("https://fixture.invalid/" + $id + ".tar.xz"), shasum: $digest}};
        {($a):build($a;$ad), ($b):build($b;$bd), ($c):build($c;$cd), master:(build($dev;$dd)+{version:$dev}), "99.9.9":{}}' \
        > "$FIXTURE/index.json"
    printf '%s\n' '{"code":0,"message":"Zig version is not supported by ZLS"}' > "$FIXTURE/zls.json"
}

digest() {
    local sum
    sum=$(shasum -a 256 < "$1") || return 1
    printf '%s\n' "${sum%% *}"
}

zig_archive() {
    local id="$1" src="$FIXTURE/zig-src"
    mkdir -p "$src/dist/lib"
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$id" > "$src/dist/zig"
    chmod +x "$src/dist/zig"
    touch "$src/dist/lib/std.zig"
    bsdtar --format=ustar -cJf "$FIXTURE/$id.tar.xz" -C "$src" dist
}

zls_archive() {
    local src="$FIXTURE/zls-src" hash
    mkdir -p "$src"
    printf '#!/bin/sh\nprintf "%%s\\n" "zls %s"\n' "$A" > "$src/zls"
    chmod +x "$src/zls"
    bsdtar --format=ustar -cJf "$FIXTURE/zls.tar.xz" -C "$src" zls
    hash=$(digest "$FIXTURE/zls.tar.xz")
    jq -n --arg p "$TARGET" --arg v "$A" --arg hash "$hash" \
        '{version:$v, ($p):{tarball:"https://fixture.invalid/zls.tar.xz",shasum:$hash}}' > "$FIXTURE/zls.json"
}

fail_test() { printf 'Test failed: %s\n' "$*" >&2; exit 1; }

snapshot() {
    # No atimes (readers are permitted), but record paths, modes, link targets,
    # mtimes and file contents so no-write and retain-foreign assertions are strict.
    local base="$1" entry
    local os; os=$(uname -s)
    (cd "$base" && LC_ALL=C find . -print | LC_ALL=C sort | while IFS= read -r entry; do
        case "$os" in
            Darwin) stat -f '%p %.9Fm %N' "$entry" ;;
            Linux) stat -c '%f %y %N' "$entry" ;;
        esac
        if [[ -L "$entry" ]]; then readlink "$entry"
        elif [[ -f "$entry" ]]; then printf 'SHA %s\n' "$(digest "$entry")"; fi
    done)
}

reaches() {
    local file="$1" pid="$2" i
    for ((i=0; i<200; i++)); do
        [[ ! -e "$file" ]] || return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep .025
    done
    return 1
}

isolated_path() {
    local dir="$1" tool path
    shift
    mkdir -p "$dir"
    for tool in "$@"; do
        path=$(command -v "$tool") || return 1
        ln -s "$path" "$dir/$tool"
    done
}
