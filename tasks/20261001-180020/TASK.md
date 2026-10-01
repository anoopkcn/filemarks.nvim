# replace vim.uv or vim.loop with vim.uv

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

`lua/filemarks/markpath.lua:7`, `lua/filemarks/store.lua:10`.

`vim.loop` has been deprecated since Nvim 0.10. Use `vim.uv` directly.

Found in the Neovim 0.13 review on 2026-10-01.

## Resolution (2026-10-01)

`lua/filemarks/markpath.lua:7` and `lua/filemarks/store.lua:10` now use `local uv = vim.uv`.
`vim.uv` exists from Nvim 0.10; the plugin needs 0.11+ anyway (`vim.fs.relpath`).
