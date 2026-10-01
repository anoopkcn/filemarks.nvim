# simplify the # comment highlight in the list buffer

- STATUS: OPEN
- PRIORITY: 100
- TAGS:

`lua/filemarks/ui/document.lua:41-74`, `:263-285`.

The `#` comment highlight uses window-scoped `matchadd`, window variables and 3 autocmds.
If `list_open_cmd` is a function that returns a window other than the current one,
`nvim_win_set_buf` does not move focus and the FileType autocmd adds the match to the
current, unrelated window.

Fix: a buffer-local `syntax match Comment /^\s*#.*/` (or `syntax/filemarks.vim`) replaces
all of it.

Found in the Neovim 0.13 review on 2026-10-01.
