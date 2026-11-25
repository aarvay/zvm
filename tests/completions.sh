#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=tests/fixture.sh
source "$root/tests/fixture.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fixture "$tmp/work space"
export COMPLETIONS="$root/completions" REAL_ZVM="$root/zvm" CALL_LOG="$tmp/calls"
export PROVIDER_HOME="$HOME" PROVIDER_DATA="$XDG_DATA_HOME" PROVIDER_CACHE="$XDG_CACHE_HOME"
"$REAL_ZVM" install "$A" --use --no-zls
"$REAL_ZVM" install "$B" --no-zls
# Incidental refreshes on Tab should fail if attempted and show up in requests.
touch -t 200001010000 "$CACHE/index.json"
touch "$FIXTURE/offline"
cat > "$TEST_BIN/zvm" <<'BASH'
#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
[[ "$1" == __complete ]] || exit 2
export HOME="$PROVIDER_HOME" XDG_DATA_HOME="$PROVIDER_DATA" XDG_CACHE_HOME="$PROVIDER_CACHE"
exec /bin/bash "$REAL_ZVM" "$@"
BASH
chmod +x "$TEST_BIN/zvm"
cd "$HOME"

# Input lines and exact candidate sets shared across all completion engines.
cat > "$tmp/cases" <<'CASES'
zvm in|install
zvm install |--no-zls --use 0.10.0 0.10.1 0.11.0-dev.12+abc123 0.9.0 latest master
zvm install 0.10.|0.10.0 0.10.1
zvm install --use |--no-zls 0.10.0 0.10.1 0.11.0-dev.12+abc123 0.9.0 latest master
zvm install 0.9.0 --use |--no-zls
zvm install --no-zls 0.9.0 |--use
zvm install --no-zls 0.9.0 --use |
zvm uninstall |--all 0.10.0
zvm uninstall --all |--yes
zvm uninstall --all --yes |
zvm uninstall 0.10.0 |
zvm zls |install
zvm zls install |0.10.0 0.9.0
zvm zls install 0.9.0 |
zvm use 0.9.0 |
zvm list |--remote
zvm list --remote |
zvm current |
CASES
export CASES="$tmp/cases" RESULT="$tmp/result"
snapshot "$tmp/work space" > "$tmp/before"

if (( $# == 0 )); then set -- bash zsh fish; fi
for shell in "$@"; do
    : > "$CALL_LOG"
    case "$shell" in
        bash)
            /bin/bash -n "$COMPLETIONS/zvm-completion.bash"
            /bin/bash <<'BASH' > "$RESULT"
set -eu
source "$COMPLETIONS/zvm-completion.bash"
while IFS='|' read -r input _; do
    read -r -a COMP_WORDS <<< "$input"
    if [[ "$input" == *' ' ]]; then COMP_WORDS+=(''); fi
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    _zvm
    printf '%s\n' "${COMPREPLY[*]-}"
done < "$CASES"
BASH
            ;;
        zsh)
            zsh -n "$COMPLETIONS/_zvm"
            export ZDOTDIR="$tmp/zdir"
            mkdir -p "$ZDOTDIR"
            # Use a real ZLE completion widget and have compadd capture its
            # prefix-filtered matches without terminal column formatting.
            cat > "$ZDOTDIR/.zshrc" <<'ZSH'
PS1='ready> '
fpath=("$COMPLETIONS" $fpath)
autoload -Uz compinit
compinit -D -i
_describe() {
    local -a values matched
    values=("${(@P)2}")
    values=("${values[@]%%:*}")
    compadd -O matched -a values
    print -r -- "${(j: :)matched}" >> "$RESULT.one"
    compadd -a values
}
zvm_test_tab() {
    : > "$RESULT.one"
    zle expand-or-complete
    print -r -- "$(<"$RESULT.one")" >> "$RESULT"
    BUFFER=''
    print -r -- $'\nDONE'
    zle reset-prompt
}
zle -N zvm_test_tab
bindkey '^I' zvm_test_tab
ZSH
            : > "$RESULT"
            expect <<'TCL' > "$tmp/pty.log" || { grep . "$tmp/pty.log" >&2; fail_test 'Zsh PTY'; }
set timeout 10
spawn -noecho zsh -d -i
proc prompt {} {
    expect {
        -exact {ready> } {}
        timeout { exit 1 }
        eof { exit 1 }
    }
}
prompt
set f [open $env(CASES) r]
while {[gets $f line] >= 0} {
    set input [lindex [split $line |] 0]
    send -- "$input\t"
    expect {
        -exact DONE {}
        timeout { exit 1 }
        eof { exit 1 }
    }
    prompt
}
close $f
send -- "exit\r"
expect {
    eof {}
    timeout { exit 1 }
}
exit [lindex [wait] 3]
TCL
            ;;
        fish)
            fish -n "$COMPLETIONS/zvm.fish"
            # Keep Fish's own first-run files separate from zvm's fixture.
            mkdir -p "$tmp/fish-home"
            # shellcheck disable=SC2016 # The quoted program is Fish, not Bash.
            HOME="$tmp/fish-home" XDG_CONFIG_HOME="$tmp/fish-config" XDG_DATA_HOME="$tmp/fish-data" \
                XDG_CACHE_HOME="$tmp/fish-cache" XDG_STATE_HOME="$tmp/fish-state" fish --no-config -c '
                source "$COMPLETIONS/zvm.fish"
                while read -d "|" -l input ignored
                    set -l candidates (complete -C "$input" | string replace -r "\t.*" "")
                    if set -q candidates[1]; string join " " -- $candidates; else; echo; end
                end < "$CASES"' > "$RESULT"
            ;;
        *) fail_test "unknown shell: $shell" ;;
    esac
    exec 8< "$RESULT"
    while IFS='|' read -r input expected; do
        IFS= read -r actual <&8 || fail_test "$shell missing result for $input"
        normalize() { printf '%s\n' "$1" | tr ' ' '\n' | LC_ALL=C sort; }
        [[ "$(normalize "$actual")" == "$(normalize "$expected")" ]] || fail_test "$shell: [$input] expected [$expected], got [$actual]"
    done < "$CASES"
    if IFS= read -r actual <&8; then fail_test "$shell returned excess results"; fi
    exec 8<&-
    expected_calls=$'__complete installable\n__complete installable\n__complete installable\n__complete inactive\n__complete installed'
    [[ "$(<"$CALL_LOG")" == "$expected_calls" ]] || fail_test "$shell called the provider in a context that did not need it"
    printf '%s candidate checks passed\n' "$shell"
done
snapshot "$tmp/work space" > "$tmp/after"
cmp "$tmp/before" "$tmp/after"

# No-cache fallback: selectors are local constants; provider returns installed.
mv "$CACHE/index.json" "$tmp/saved-index"
expected=$(printf '%s\t\n%s\tselected\n' "$B" "$A")
[[ "$(zvm __complete installable)" == "$expected" ]]
rm -rf "$CACHE"
[[ "$(zvm __complete installed)" == "$expected" && ! -e "$CACHE" ]]
