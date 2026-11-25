#!/usr/bin/env bash
_zvm() {
    local cur="${COMP_WORDS[COMP_CWORD]}" cmd="${COMP_WORDS[1]:-}" options='' mode='' token candidate i
    local used_spec=no used_use=no used_no_zls=no
    COMPREPLY=()
    if (( COMP_CWORD == 1 )); then
        options='install use unset current list uninstall zls --help --version'
    else
        case "$cmd" in
            install)
                for ((i=2; i<COMP_CWORD; i++)); do
                    token="${COMP_WORDS[i]}"
                    case "$token" in
                        --use) [[ "$used_use" == no ]] || return 0; used_use=yes ;;
                        --no-zls) [[ "$used_no_zls" == no ]] || return 0; used_no_zls=yes ;;
                        -*|'') return 0 ;;
                        *) [[ "$used_spec" == no ]] || return 0; used_spec=yes ;;
                    esac
                done
                [[ "$used_use" == yes ]] || options+=' --use'
                [[ "$used_no_zls" == yes ]] || options+=' --no-zls'
                if [[ "$used_spec" == no && "$cur" != -* ]]; then options+=' latest master'; mode=installable; fi
                ;;
            use) if (( COMP_CWORD == 2 )); then mode=installed; fi ;;
            list) if (( COMP_CWORD == 2 )); then options=--remote; fi ;;
            uninstall)
                if (( COMP_CWORD == 2 )); then options=--all; mode=inactive
                elif (( COMP_CWORD == 3 )) && [[ "${COMP_WORDS[2]}" == --all ]]; then options=--yes; fi
                ;;
            zls)
                if (( COMP_CWORD == 2 )); then options=install
                elif (( COMP_CWORD == 3 )) && [[ "${COMP_WORDS[2]}" == install ]]; then mode=installed; fi
                ;;
        esac
    fi
    if [[ -n "$mode" && "$cur" != -* ]]; then
        while IFS=$'\t' read -r candidate _; do options+=" $candidate"; done < <(zvm __complete "$mode" 2>/dev/null)
    fi
    while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -W "$options" -- "$cur")
    return 0
}
complete -F _zvm zvm
