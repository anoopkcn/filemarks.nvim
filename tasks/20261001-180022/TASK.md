# simplify the # comment highlight in the list buffer

- STATUS: CLOSED
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

## Resolution (2026-10-01)

Replaced the `matchadd` machinery with a syntax file.

- New `syntax/filemarks.vim`: `syntax match filemarksComment /^\s*#.*/`, linked to
  `Comment` (`highlight default link`, so colorschemes can override it).
- `lua/filemarks/ui/document.lua`: removed `ensure_comment_match`, `clear_comment_match`,
  `configure_comment` and `install_filetype_support` (the FileType/BufWinEnter/BufWinLeave
  autocmds). `create()` sets `commentstring = "# %s"` on the buffer directly.
- `lua/filemarks/ui/editor.lua`, `lua/filemarks/init.lua`: dropped the calls to those
  helpers; `lua/filemarks/state.lua`: dropped `filetype_autocmd`.

Checked headless with a `list_open_cmd` function that returns a window it leaves
unfocused: line 1 of the list has syntax group `filemarksComment`, mark lines have
none, `commentstring` is `# %s`, and no window has matches.

Trade-off: highlighting now follows `:syntax`. A user who runs `:syntax off` gets no
comment highlight in the list (previously `matchadd` worked regardless).
