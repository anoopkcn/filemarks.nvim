# minor: dir marks always :edit in the current window; eager store.load

- STATUS: OPEN
- PRIORITY: 100
- TAGS:

- `lua/filemarks/marks.lua:225-229`: directory marks always `:edit` in the current
  window, while file marks focus an existing window showing the file. Make them
  consistent.
- `setup()` eagerly runs `store.load()`, which does realpath + stat on every stored mark
  at startup. Load lazily on first use.

Found in the Neovim 0.13 review on 2026-10-01.
