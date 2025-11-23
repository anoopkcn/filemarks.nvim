local M = {}

function M.reset(default_config)
    local commands_installed = M.commands_installed
    local filetype_autocmd = M.filetype_autocmd
    M.config = vim.deepcopy(default_config)
    M.data = {}
    M.keymaps = {}
    M.action_keymaps = {}
    M.goto_prefix_keymap = nil
    M.loaded = false
    M.commands_installed = commands_installed
    M.filetype_autocmd = filetype_autocmd
end

function M.key_in_use(key)
    for _, marks in pairs(M.data or {}) do
        if marks[key] then
            return true
        end
    end
    return false
end

return M
