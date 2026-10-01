if vim.g.loaded_filemarks then
    return
end
vim.g.loaded_filemarks = 1

require("filemarks.config")
require("filemarks.commands").install()

-- setup()/configure() already ran (e.g. from init.lua before vim.pack sourced
-- this file) and installed the keymaps under the user's settings
if require("filemarks.state").configured then
    return
end

local keymaps = require("filemarks.keymaps")
keymaps.install_default_action_keymaps()
keymaps.install_goto_prefix_fallback()
