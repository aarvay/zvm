#!/bin/zsh
# Manual loader; behavioral checks live in tests/completions.sh.
# Source this file in an interactive Zsh session from any directory.
fpath=("${${(%):-%x}:A:h}/completions" $fpath)
autoload -Uz compinit
compinit -D
printf '%s\n' 'Try: zvm install <Tab>, zvm uninstall --all <Tab>, zvm zls install <Tab>'
