if vim.g.loaded_filemarks then
    return
end
vim.g.loaded_filemarks = 1

require("filemarks.config")
require("filemarks.commands").install()

local keymaps = require("filemarks.keymaps")
keymaps.install_default_action_keymaps()
keymaps.install_goto_prefix_fallback()
