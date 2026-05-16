-- LICENSE: MIT
-- by @anoopkcn
-- Description: A Neovim plugin to manage persistent marks for files and directories per project.

local config = require("filemarks.config")
local storage = require("filemarks.storage")
local keymaps = require("filemarks.keymaps")
local marks = require("filemarks.marks")
local commands = require("filemarks.commands")
local editor_ui = require("filemarks.ui.editor")

local M = {}

function M.configure(opts)
    config.configure(opts or {})
    storage.load()
    marks.install_action_keymaps()
    keymaps.install_goto_prefix_fallback()
end

local function install_project_cache_invalidation()
    local group = vim.api.nvim_create_augroup("FilemarksProjectCache", { clear = true })
    vim.api.nvim_create_autocmd({ "BufFilePost", "BufNewFile" }, {
        group = group,
        callback = function(ev)
            vim.b[ev.buf].filemarks_project_cached = nil
        end,
    })
end

function M.setup(opts)
    M.configure(opts or {})
    commands.install()
    editor_ui.install_filetype_support()
    install_project_cache_invalidation()
end

M.add = marks.add
M.add_dir = marks.add_dir
M.remove = marks.remove
M.list = marks.list
M.open = marks.open

return M
