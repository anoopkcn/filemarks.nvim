local state = require("filemarks.state")

local M = {}

local function call_open(key)
    require("filemarks.marks").open(key)
end

local function clear_keymap(key)
    local lhs = state.keymaps[key]
    if lhs then
        pcall(vim.keymap.del, "n", lhs)
        state.keymaps[key] = nil
    end
end

function M.ensure_jump_keymap(key, opts)
    if state.keymaps[key] or not state.config.goto_prefix or state.config.goto_prefix == "" then
        return
    end
    local lhs = state.config.goto_prefix .. key
    if vim.fn.maparg(lhs, "n") ~= "" then
        if not (opts and opts.silent) then
            vim.notify(
                string.format("Filemarks: %s is already mapped - skipping jump keymap for '%s'", lhs, key),
                vim.log.levels.WARN
            )
        end
        return
    end
    vim.keymap.set("n", lhs, function()
        call_open(key)
    end, { desc = string.format("Filemarks: jump to %s", key) })
    state.keymaps[key] = lhs
end

function M.rebuild_jump_keymaps()
    local should_exist = {}
    for _, marks in pairs(state.data) do
        for key in pairs(marks) do
            should_exist[key] = true
        end
    end

    for key in pairs(state.keymaps) do
        if not should_exist[key] then
            clear_keymap(key)
        end
    end

    for key in pairs(should_exist) do
        M.ensure_jump_keymap(key)
    end
end

function M.install_action_keymaps(actions)
    local prefix = state.config.action_prefix
    if not prefix or prefix == "" then
        return
    end
    for _, action in ipairs(actions) do
        local lhs = prefix .. action.key
        vim.keymap.set("n", lhs, action.fn, { desc = "Filemarks: " .. action.desc })
        table.insert(state.action_keymaps, lhs)
    end
end

local function handle_prefix_jump()
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok or not key or key == "" then
        return
    end
    if key == "\027" or key == "<Esc>" then
        return
    end
    call_open(key)
end

function M.install_goto_prefix_fallback()
    local prefix = state.config.goto_prefix
    if not prefix or prefix == "" then
        return
    end
    vim.keymap.set("n", prefix, handle_prefix_jump, { desc = "Filemarks: jump to mark" })
    state.goto_prefix_keymap = prefix
end

function M.reset_keymaps()
    if type(state.keymaps) == "table" then
        for _, lhs in pairs(state.keymaps) do
            pcall(vim.keymap.del, "n", lhs)
        end
    end
    if type(state.action_keymaps) == "table" then
        for _, lhs in ipairs(state.action_keymaps) do
            pcall(vim.keymap.del, "n", lhs)
        end
    end
    if state.goto_prefix_keymap then
        pcall(vim.keymap.del, "n", state.goto_prefix_keymap)
    end
    state.keymaps = {}
    state.action_keymaps = {}
    state.goto_prefix_keymap = nil
end

return M
