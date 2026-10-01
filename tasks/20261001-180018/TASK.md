# drop the netrw code path; Nvim 0.13 dir buffers already work

- STATUS: OPEN
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
