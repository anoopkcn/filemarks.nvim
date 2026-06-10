-- Window placement for the filemarks list: find, acquire, close.
-- Two adapters satisfy "give me a window": command modifiers
-- (:bot FilemarksToggle -> 'bot split') and the list_open_cmd setting.
-- Knows nothing about the document beyond a buffer predicate.

local state = require("filemarks.state")

local notify = vim.notify
local log = vim.log.levels

local M = {}

--- First window whose buffer satisfies `matches(buf)`.
function M.find_window(matches)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_loaded(buf) and matches(buf) then
            return win, buf
        end
    end
    return nil
end

--- Produce a window for the list. Adapters in order: command mods,
--- list_open_cmd (function or string), current window as fallback.
function M.acquire(mods)
    if type(mods) == "string" and mods ~= "" then
        -- split (not new) so no stray empty buffer is created; the caller
        -- replaces the window's buffer right after
        local ok = pcall(vim.cmd, mods .. " split")
        if ok then
            return vim.api.nvim_get_current_win()
        end
    end

    local open_cmd = state.config.list_open_cmd
    if type(open_cmd) == "function" then
        local ok, result = pcall(open_cmd)
        if ok and type(result) == "number" and vim.api.nvim_win_is_valid(result) then
            return result
        end
    elseif type(open_cmd) == "string" and open_cmd ~= "" then
        pcall(vim.cmd, open_cmd)
    end

    return vim.api.nvim_get_current_win()
end

--- Close the window; if closing fails (e.g. last window), swap in the
--- alternate buffer or a fresh one. Always returns true ("handled").
function M.close(win, buf)
    local ok = pcall(vim.api.nvim_win_close, win, false)
    if ok then
        return true
    end
    local alt = vim.api.nvim_win_call(win, function()
        return vim.fn.bufnr("#")
    end)
    local fallback, created
    if alt > 0 and alt ~= buf and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
        fallback = alt
    else
        fallback = vim.api.nvim_create_buf(true, false)
        created = true
    end
    local swapped, err = pcall(vim.api.nvim_win_set_buf, win, fallback)
    if not swapped then
        if created then
            pcall(vim.api.nvim_buf_delete, fallback, { force = true })
        end
        notify(string.format("Filemarks: unable to close window: %s", err), log.WARN)
    end
    return true
end

return M
