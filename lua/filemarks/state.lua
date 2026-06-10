local M = {}

function M.reset(default_config)
    local commands_installed = M.commands_installed
    local filetype_autocmd = M.filetype_autocmd
    local project_cache_autocmd = M.project_cache_autocmd
    M.config = vim.deepcopy(default_config)
    M.data = {}
    M.dirty = false
    M.keymaps = {}
    M.action_keymaps = {}
    M.goto_prefix_keymap = nil
    M.loaded = false
    M.loaded_path = nil
    M.load_failed = false
    M.commands_installed = commands_installed
    M.filetype_autocmd = filetype_autocmd
    M.project_cache_autocmd = project_cache_autocmd
end

return M
