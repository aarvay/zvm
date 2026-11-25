#!/usr/bin/env bash
set -euo pipefail

# Release template; scripts/build-release.sh fills in these values.
readonly REPO='@REPOSITORY@'
readonly TAG='@TAG@'
readonly SHA256='@SHA256@'
readonly PAYLOAD_MARKER='# zvm GitHub release payload v1'

fail() { printf 'Installer: %s\n' "$*" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }

has_archive_reader() {
    local tool version
    for tool in bsdtar tar; do
        version=$(LC_ALL=C "$tool" --version 2>/dev/null) || continue
        [[ "$version" == bsdtar\ * && "$version" == *liblzma/* ]] && return 0
    done
    return 1
}

check_dependencies() {
    local os="$1" tool package required=no
    local -a missing=() packages=()
    if command -v sha256sum >/dev/null; then HASHER=(sha256sum)
    elif command -v shasum >/dev/null; then HASHER=(shasum -a 256)
    else HASHER=(); missing+=('sha256sum or shasum'); required=yes
        if [[ "$os" == Linux ]]; then packages+=(coreutils); fi
    fi
    for tool in curl flock jq bsdtar; do
        if [[ "$tool" == bsdtar ]]; then has_archive_reader && continue
        else command -v "$tool" >/dev/null && continue; fi
        missing+=("$tool")
        case "$tool" in curl|flock) required=yes ;; esac
        case "$os:$tool" in
            Darwin:flock|Darwin:jq|Linux:curl|Linux:jq) package="$tool" ;;
            Darwin:bsdtar|Linux:bsdtar) if [[ "$os" == Darwin ]]; then package=libarchive; else package=libarchive-tools; fi ;;
            Linux:flock) package=util-linux ;;
            *) continue ;;
        esac
        packages+=("$package")
    done
    if (( ${#missing[@]} )); then
        printf 'Missing tools: %s\n' "${missing[*]}" >&2
        if (( ${#packages[@]} )); then
            if [[ "$os" == Darwin ]] && command -v brew >/dev/null; then
                printf 'Install missing packages with: brew install %s\n' "${packages[*]}" >&2
            elif [[ "$os" == Linux ]] && command -v apt-get >/dev/null; then
                printf 'Install missing packages with: sudo apt-get install %s\n' "${packages[*]}" >&2
            else
                printf 'Install the missing tools with your package manager.\n' >&2
            fi
        fi
    fi
    [[ "$required" == no ]] || fail 'Install the missing bootstrap dependencies, then retry'
}

prepare_dir() {
    local root="$1" dir="$2" part path="$1" rest
    [[ "$dir" == "$root/"* ]] || fail 'Choose an install directory under HOME, not a system prefix'
    rest="${dir#"$root/"}"
    case "/$rest/" in *//*|*/./*|*/../*|*[[:cntrl:]]*) fail 'Use a normalized install directory' ;; esac
    # Verify ancestors before creating missing parents; never follow symlinks.
    while [[ -n "$rest" ]]; do
        part="${rest%%/*}"
        if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=''; fi
        path="$path/$part"
        ! exists "$path" || [[ -d "$path" && ! -L "$path" ]] || fail "Unexpected directory: $path"
        if [[ -d "$path/Cellar" || -d "$path/conda-meta" || -e "$path/bin/brew" ]]; then
            fail 'Choose an install directory outside package-manager prefixes'
        fi
    done
    mkdir -p -- "$dir" || fail 'Cannot create install directory'
}

is_release_payload() {
    [[ -f "$1" && ! -L "$1" ]] || return 1
    local line i
    for ((i=0; i<8; i++)); do
        IFS= read -r line || return 1
        if [[ "$line" == "$PAYLOAD_MARKER" ]]; then return 0; fi
    done < "$1"
    return 1
}

cleanup() {
    if [[ -n "$TRANSFER" ]]; then
        kill "$TRANSFER" 2>/dev/null || :
        wait "$TRANSFER" 2>/dev/null || :
    fi
    if [[ -n "$TMP" ]]; then rm -f -- "$TMP"; fi
}

main() {
    [[ $# == 0 ]] || fail 'This installer accepts no arguments'
    [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ &&
        "$SHA256" =~ ^[a-f0-9]{64}$ ]] || fail 'Use a generated installer from a tagged release'
    [[ -n "${HOME:-}" && "$HOME" == /* ]] || fail 'HOME must be absolute'
    [[ ${EUID:-0} != 0 ]] || fail 'Do not run this installer as root or with sudo'
    local os dir sum home dest
    os=$(uname -s)
    case "$os" in Darwin|Linux) ;; *) fail 'Supported systems: macOS and Linux' ;; esac
    check_dependencies "$os"
    home=$(cd -P -- "$HOME" && pwd -P) || fail 'Cannot resolve HOME'
    dir="${ZVM_INSTALL_DIR:-$HOME/.local/bin}"
    dir="${dir%/}"
    if [[ "$dir" == "${HOME%/}/"* ]]; then dir="$home/${dir#"${HOME%/}/"}"; fi
    prepare_dir "$home" "$dir"
    dest="$dir/zvm"
    exec 9<"$dir" || fail 'Cannot open install directory for locking'
    flock -n 9 || fail 'Cannot acquire installer lock'
    if exists "$dest"; then is_release_payload "$dest" || fail "Refusing to replace unrelated path: $dest"; fi

    TMP='' TRANSFER=''
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    TMP=$(mktemp "$dir/.zvm-download.XXXXXXXX") || fail 'Cannot stage download'
    curl -qfsSL --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 300 \
        -o "$TMP" -- "https://github.com/$REPO/releases/download/$TAG/zvm" 9<&- &
    TRANSFER=$!
    local status=0
    wait "$TRANSFER" || status=$?
    TRANSFER=''
    (( status == 0 )) || fail 'Download failed'
    sum=$("${HASHER[@]}" < "$TMP") || fail 'Cannot hash download'
    [[ "${sum%% *}" == "$SHA256" ]] || fail 'Checksum mismatch; existing manager unchanged'
    is_release_payload "$TMP" || fail 'Unrecognized release payload'
    chmod 755 "$TMP" || fail 'Cannot set executable mode'
    if exists "$dest"; then
        is_release_payload "$dest" || fail "Refusing to replace unrelated path: $dest"
        case "$os" in
            Darwin) mv -fh -- "$TMP" "$dest" || fail 'Cannot publish manager' ;;
            Linux) mv -fT -- "$TMP" "$dest" || fail 'Cannot publish manager' ;;
        esac
    else
        case "$os" in
            Darwin) mv -nh -- "$TMP" "$dest" || fail 'Cannot publish manager' ;;
            Linux) mv -nT -- "$TMP" "$dest" || fail 'Cannot publish manager' ;;
        esac
        ! exists "$TMP" || fail 'Destination appeared during installation'
    fi
    printf 'Installed zvm %s to %s\n' "$TAG" "$dest"
    if [[ ":${PATH:-}:" != *":$dir:"* ]]; then printf 'Add %s to PATH in your shell configuration.\n' "$dir"; fi
    printf 'Zig activation uses %s/.local/bin. Shell completions are opt-in.\n' "$HOME"
}

main "$@"
