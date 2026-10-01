# rename the buffer key to buf (soft-deprecated in Nvim 0.13)

- STATUS: OPEN
- PRIORITY: 100
- TAGS:

`lua/filemarks/ui/document.lua:189`, `:202` (`nvim_create_autocmd`) and `:246`, `:255`
(`vim.keymap.set`).

Nvim 0.13 renamed the `buffer` key to `buf`. `buffer` is still accepted;
`runtime/lua/vim/keymap.lua` notes "soft-deprecate `buffer` in 0.13, remove in 0.15".

Trade-off: `buf` in the autocmd API exists only from 0.13, so switching drops 0.12
support. Decide the minimum supported Nvim version first.

Found in the Neovim 0.13 review on 2026-10-01.

## Findings (checked 2026-10-01)

Decision: minimum supported Nvim stays 0.11 (needed for `vim.fs.relpath`); 0.13 is still
a dev build. Keep `buffer` for now: it works through 0.14 and is only removed in 0.15.
The minimum is now stated in `README.md` (Installation) and `doc/filemarks.txt`
(Quick start).

Remaining uses of `buffer =` (line numbers moved after 20261001-180022):
`lua/filemarks/ui/document.lua` `setup_buffer_autocmds()` (BufUnload, BufWriteCmd) and
`create()` (`<CR>` and `list_close_key` keymaps).

Revisit when 0.13 is released and the minimum can move to 0.13: rename the four keys to
`buf` and bump the stated minimum. Must be done before 0.15.

Q1: When does the minimum move to 0.13 (on 0.13 release, or later)?
