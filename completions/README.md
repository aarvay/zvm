# Shell completions

Install `zvm` on PATH first. Completion files are included in the release source bundle; the standalone installer does not edit profiles or install them.

- **Bash:** Save `zvm-completion.bash` in `~/.local/share/bash-completion/completions/zvm` if you use bash-completion, or add `source /path/to/zvm-completion.bash` to your Bash config. No shell framework is required when sourced directly.
- **Zsh:** Save `_zvm` in a directory on `fpath` before `autoload -Uz compinit && compinit` in your Zsh config.
- **Fish:** Save `zvm.fish` in `${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions/`.

Tab suggests valid next tokens. `install` offers `latest`, `master`, and concrete platform builds from the existing index cache, plus installed versions. `use` and `zls install` suggest installed Zig; `uninstall` excludes the selected version. Completions never download or update the cache. To populate it explicitly, run `zvm list --remote`.

Test with `/bin/bash tests/completions.sh` from the checkout (requires Bash, Zsh, Fish and Expect).
