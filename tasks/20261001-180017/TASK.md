# strip_scheme turns term:// and fugitive:// buffers into bogus marks

- STATUS: OPEN
- PRIORITY: 100
- TAGS:

`lua/filemarks/markpath.lua:20-29` (commit f1e68de "strip URI scheme... oil").

`strip_scheme` was added for oil buffers but strips any scheme. Marking a
`term://~/x//123:/bin/zsh` or `fugitive:///repo/.git//<sha>/f` buffer silently stores a
path that does not exist (`x/123:/bin/zsh`, a `.git/...` path).

oil is no longer used (dotfiles moved to the builtin `:h dir` listing), so:
fix by reverting f1e68de, or refuse to mark when `vim.bo.buftype ~= ""` or the stripped
path does not exist.

Note: `~/develop/filemarks.nvim` is a detached HEAD at 0479381; the copy vim.pack loads is
at f1e68de (one commit ahead). Check out `main` and pull before working on this.

Found in the Neovim 0.13 review on 2026-10-01.
