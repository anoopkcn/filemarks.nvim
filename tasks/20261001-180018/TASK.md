# drop the netrw code path; Nvim 0.13 dir buffers already work

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

`lua/filemarks/marks.lua:29-35`, description in `lua/filemarks/commands.lua:24`
("detects netrw directory").

In Nvim 0.13 editing a directory opens a `filetype=directory` buffer named by its path
(`:h dir`), so the plain bufname fallback already handles it. Checked headless:
`add_dir("s")` from a dir buffer stored `sub`, and jumping with
`dir_open_cmd = "edit %s"` reopened it.

Fix: drop the `netrw_curdir` branch (or keep it only for `:Explore`) and update the
command description.

Found in the Neovim 0.13 review on 2026-10-01.

## Resolution (2026-10-01)

Dropped the `netrw_curdir` branch entirely, including for `:Explore`: netrw names its
buffer after the directory it shows (`:Explore` from `lua/filemarks/marks.lua` gives
bufname `lua/filemarks/`, same as `b:netrw_curdir`), so the bufname fallback covers it.

- `lua/filemarks/marks.lua`: `current_dir_context()` = directory buffer itself, else its
  parent, else cwd.
- `lua/filemarks/commands.lua`: `:FilemarksAddDir` description no longer says "detects
  netrw directory".
- `README.md` (`:FilemarksAddDir` section), `doc/filemarks.txt` (3.2 and the
  `filemarks.add_dir()` example): describe the directory-buffer rule instead of netrw.

Checked headless (Nvim 0.13-dev): `add_dir` from a netrw buffer stored `lua/filemarks/`,
from `:edit lua` stored `lua/`; jumping with `dir_open_cmd = "edit %s"` reopened the dir.
