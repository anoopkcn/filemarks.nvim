local state = require("filemarks.state")
local keymaps = require("filemarks.keymaps")

local default_config = {
    goto_prefix = "<leader>m",
    action_prefix = "<leader>M",
    storage_path = vim.fn.stdpath("state") .. "/filemarks.json",
    project_markers = { ".git", ".hg", ".svn" },
    dir_open_cmd = nil,
    list_open_cmd = nil,
    show_help = true,
}

local M = {}

function M.configure(opts)
    keymaps.reset_keymaps()
    state.reset(default_config)
    state.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
end

function M.get()
    return state.config
end

M.default_config = default_config

state.reset(default_config)

return M
