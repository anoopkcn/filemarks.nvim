# minor: dir marks always :edit in the current window; eager store.load

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

- `lua/filemarks/marks.lua:225-229`: directory marks always `:edit` in the current
  window, while file marks focus an existing window showing the file. Make them
  consistent.
- `setup()` eagerly runs `store.load()`, which does realpath + stat on every stored mark
  at startup. Load lazily on first use.

Found in the Neovim 0.13 review on 2026-10-01.

## Resolution (2026-10-01)

- Directory marks: `lua/filemarks/marks.lua` `M.show()` first focuses a window already
  showing the directory (`focus_buffer_for_path(path, true)`), otherwise it calls
  `dir_open_cmd` as before. `window_only` because a hidden-but-loaded directory buffer
  should still go through `dir_open_cmd` instead of `:buffer`. The lookup now skips
  `filetype=filemarks` buffers: `Filemarks:///proj` strips to the project directory, so
  a `.` mark would otherwise jump into the list window.
- Lazy load: `lua/filemarks/init.lua` `setup()` no longer calls `store.load()`; the store
  already loads on first `get`/`set`/`marks_for`, and `sync_jump_keymaps` is a no-op
  until then. Removed the now unused `store.M.load`. Until the first load, jumps go
  through the `goto_prefix` fallback mapping; per-mark keymaps (and their which-key
  descriptions) appear after it.
- Docs: `README.md` and `doc/filemarks.txt` (`setup()`, `configure()`, `:FilemarksAddDir`,
  `:FilemarksOpen`, list `<CR>`) describe both changes.

Checked headless: after `setup()` there are 0 jump keymaps, 3 after the first jump;
`l -> lua/` with `lua/` open in another window focused that window; `p -> .` with the list
open opened the project dir in the current window instead of focusing the list.
