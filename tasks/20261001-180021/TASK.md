# keymaps are installed twice (setup + plugin/)

- STATUS: CLOSED
- PRIORITY: 100
- TAGS:

`plugin/filemarks.lua` and `setup()`.

With `vim.pack.add` at startup, `setup()` runs from init.lua and then
`plugin/filemarks.lua` is sourced and installs the action keymaps and prefix fallback
again, so `state.action_keymaps` holds every lhs twice. Harmless (`reset_keymaps` deletes
with pcall) but redundant.

Fix: have `plugin/` skip work once `setup()` has run, or make `setup()` only configure
and load.

Found in the Neovim 0.13 review on 2026-10-01.

## Resolution (2026-10-01)

`plugin/` now skips its keymap installs once `setup()`/`configure()` has run.

- `lua/filemarks/state.lua`: new session flag `configured`.
- `lua/filemarks/init.lua`: `configure()` (and so `setup()`) sets `state.configured = true`.
- `plugin/filemarks.lua`: still installs the commands (idempotent), then returns early
  when `state.configured` is set.

The other order (plugin/ first, `setup()` later, e.g. lazy.nvim `config`) was already
fine: `configure()` calls `reset_keymaps()` before reinstalling.

Checked headless with an init.lua that calls `setup({ action_prefix = "," })` before
plugin/ is sourced: `state.action_keymaps` holds 5 entries (`,a ,d ,r ,l ,t`), and
without `setup()` the 5 defaults (`<leader>Ma` …).
