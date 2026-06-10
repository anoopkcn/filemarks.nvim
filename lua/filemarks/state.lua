local M = {}

-- Replaceable settings - swapped wholesale by config.configure().
-- Mark data is NOT here: it lives behind the store (store.lua) and
-- survives reconfiguration.
M.config = nil

-- Keymap projection bookkeeping - cleared and rebuilt on configure
M.keymaps = {}
M.action_keymaps = {}
M.goto_prefix_keymap = nil

-- Session-scoped install guards - set once, never reset
M.commands_installed = false
M.filetype_autocmd = nil
M.project_cache_autocmd = nil

return M
