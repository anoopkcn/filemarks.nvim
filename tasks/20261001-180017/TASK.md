# strip_scheme turns term:// and fugitive:// buffers into bogus marks

- STATUS: CLOSED
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

## Resolution (2026-10-01)

Kept oil support (README still suggests `dir_open_cmd = "Oil %s"`) and made the strip
conditional instead of reverting f1e68de:

- `lua/filemarks/markpath.lua`: `strip_scheme` strips a scheme only when the rest exists
  on disk (`uv.fs_stat`). New `markpath.is_uri(path)` is true for a name that still
  carries a scheme after that. `resolve_absolute` returns nil for such names, so the
  list editor rejects them too ("Could not resolve path on line N").
- `lua/filemarks/marks.lua`: `add()` refuses with "Filemarks: <name> is not a file on
  disk"; `current_dir_context()` skips URI buffer names and falls back to the cwd.

Checked headless: `oil:///…/lua/` and `oil:/…/lua` store `lua`; `term://~/x//123:/bin/zsh`
and `fugitive:///…/.git//abc123/README.md` are refused; `C:/foo/bar`, relative and
not-yet-existing paths are unchanged.

Left as is: `fugitive:///repo/.git//` (status buffer) strips to the existing `.git` dir and
would mark it. Low impact; a `buftype` check could cover it if it matters.
