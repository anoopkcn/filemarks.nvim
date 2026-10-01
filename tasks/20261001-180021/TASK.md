# keymaps are installed twice (setup + plugin/)

- STATUS: OPEN
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
