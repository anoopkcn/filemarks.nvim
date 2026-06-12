-- The list document: the editable "<key> -> <path>" buffer for a project.
-- Owns rendering, parsing (the round-trip invariant), buffer construction,
-- and the buffer's display niceties (filetype, comment highlight).
-- Knows nothing about window placement.

local state = require("filemarks.state")
local markpath = require("filemarks.markpath")
local store = require("filemarks.store")

local notify = vim.notify
local log = vim.log.levels

local M = {}

local NAME_PREFIX = "Filemarks://"

function M.buffer_name(project)
    return NAME_PREFIX .. project
end

function M.is_list_buffer(buf)
    return vim.api.nvim_buf_get_name(buf):match("^Filemarks://") ~= nil
end

function M.find_buffer(name)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == name then
            return buf
        end
    end
    return nil
end

function M.has_unsaved_changes(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return false
    end
    return vim.api.nvim_get_option_value("modified", { buf = buf }) == true
end

function M.ensure_comment_match(win)
    local target_win = win or vim.api.nvim_get_current_win()
    if not target_win or not vim.api.nvim_win_is_valid(target_win) then
        return
    end
    local buf = vim.api.nvim_win_get_buf(target_win)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    if vim.w[target_win].filemarks_comment_match then
        return
    end
    local id = vim.api.nvim_win_call(target_win, function()
        return vim.fn.matchadd("Comment", "^\\s*#.*")
    end)
    vim.w[target_win].filemarks_comment_match = id
end

function M.clear_comment_match(win)
    local target_win = win or vim.api.nvim_get_current_win()
    if not target_win or not vim.api.nvim_win_is_valid(target_win) then
        return
    end
    local existing = vim.w[target_win].filemarks_comment_match
    if existing then
        pcall(vim.fn.matchdelete, existing, target_win)
        vim.w[target_win].filemarks_comment_match = nil
    end
end

function M.configure_comment(buf, win)
    vim.api.nvim_set_option_value("commentstring", "# %s", { buf = buf })
    M.ensure_comment_match(win)
end

local function generate_lines(project, marks)
    local lines = {}

    if state.config.show_help then
        local open_help = "# Press <CR> on a line to open that mark"
        local close_key = state.config.list_close_key
        if close_key and close_key ~= "" then
            open_help = string.format("%s, %s to close this window", open_help, close_key)
        end
        vim.list_extend(lines, {
            string.format("# Filemarks for %s", project),
            "# Format: <key> -> <path>. Directories should have a trailing '/'",
            open_help,
            "",
        })
    end

    local keys = vim.tbl_keys(marks or {})
    table.sort(keys)

    for _, key in ipairs(keys) do
        local stored = marks[key]
        local mark = markpath.resolve(stored, project)
        local display = mark and mark.display or markpath.relativize(stored, project)
        table.insert(lines, string.format("%s -> %s", key, display or ""))
    end

    return lines
end

--- Render marks into the buffer and clear the modified flag.
function M.refresh(buf, project, marks)
    local lines = generate_lines(project, marks)
    if vim.tbl_isempty(lines) then
        lines = { "" }
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    return lines
end

--- Grammar of a single list line.
--- @return string kind "mark"|"skip"|"invalid"
--- @return string|nil key, string|nil path (only for "mark")
local function classify_line(line)
    local trimmed = vim.trim(line)
    if trimmed == "" or vim.startswith(trimmed, "#") then
        return "skip"
    end
    local key, path = trimmed:match("^(%S+)%s*%->%s*(.+)$")
    if not key then
        return "invalid"
    end
    return "mark", key, path
end

--- Parse buffer lines back into a marks table (stored form), or nil + error.
--- The inverse of refresh: render -> parse is the document's invariant.
local function parse_buffer(buf, project)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local parsed = {}
    for idx, line in ipairs(lines) do
        local kind, key, path = classify_line(line)
        if kind == "invalid" then
            return nil, string.format("Line %d is invalid. Expected '<key> -> <path>'", idx)
        elseif kind == "mark" then
            if parsed[key] then
                return nil, string.format("Duplicate key '%s' detected on line %d", key, idx)
            end
            local mark = markpath.resolve(path, project)
            if not mark then
                return nil, string.format("Could not resolve path on line %d", idx)
            end
            parsed[key] = mark.stored
        end
    end
    return parsed
end

--- Open the mark on the cursor line of the current list buffer.
function M.open_mark_at_cursor()
    local buf = vim.api.nvim_get_current_buf()
    local project = vim.b[buf].filemarks_project
    if not project then
        return
    end
    local kind, _, path = classify_line(vim.api.nvim_get_current_line())
    if kind == "skip" then
        return
    end
    if kind == "invalid" then
        notify("Filemarks: line is not a mark. Expected '<key> -> <path>'", log.WARN)
        return
    end
    local mark = markpath.resolve(path, project)
    if not mark then
        notify("Filemarks: could not resolve path on this line", log.ERROR)
        return
    end
    if M.has_unsaved_changes(buf) then
        -- bufhidden=wipe: leaving a modified list discards its edits
        notify("Filemarks: save your changes (:w) before opening a mark", log.WARN)
        return
    end
    -- lazy require: marks.lua requires this module through ui/editor
    require("filemarks.marks").show(mark)
end

local function setup_buffer_autocmds(buf)
    local augroup = vim.api.nvim_create_augroup("FilemarksBuffer_" .. buf, { clear = true })

    vim.api.nvim_create_autocmd("BufUnload", {
        group = augroup,
        buffer = buf,
        callback = function()
            if vim.api.nvim_buf_is_valid(buf) then
                if M.has_unsaved_changes(buf) then
                    notify("Filemarks: buffer closed without saving - changes discarded", log.WARN)
                end
                vim.api.nvim_set_option_value("modified", false, { buf = buf })
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        group = augroup,
        buffer = buf,
        callback = function()
            local project = vim.b[buf].filemarks_project
            if not project then
                notify("Filemarks: unable to determine project for editor buffer", log.ERROR)
                return
            end
            local parsed, parse_err = parse_buffer(buf, project)
            if not parsed then
                notify(string.format("Filemarks: %s", parse_err), log.ERROR)
                return
            end
            store.replace(project, parsed)
            vim.api.nvim_set_option_value("modified", false, { buf = buf })
            notify("Filemarks: saved changes", log.INFO)
        end,
    })
end

--- Create the document buffer for a project and show it in `win`.
function M.create(win, project, marks)
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "filemarks", { buf = buf })
    vim.api.nvim_buf_set_name(buf, M.buffer_name(project))
    vim.b[buf].filemarks_project = project
    local lines = M.refresh(buf, project, marks)
    M.configure_comment(buf, win)

    if marks and not vim.tbl_isempty(marks) then
        for i, line in ipairs(lines) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" and not vim.startswith(trimmed, "#") then
                vim.api.nvim_win_set_cursor(win, { i, 0 })
                break
            end
        end
    end

    setup_buffer_autocmds(buf)
    vim.keymap.set("n", "<CR>", M.open_mark_at_cursor, {
        buffer = buf,
        desc = "Filemarks: open mark on this line",
    })
    local close_key = state.config.list_close_key
    if close_key and close_key ~= "" then
        vim.keymap.set("n", close_key, function()
            -- lazy require: editor.lua requires this module
            require("filemarks.ui.editor").close_editor()
        end, {
            buffer = buf,
            desc = "Filemarks: close list window",
        })
    end
    vim.b[buf].filemarks_initialized = true
    return buf
end

function M.install_filetype_support()
    if state.filetype_autocmd then
        return
    end
    local group = vim.api.nvim_create_augroup("FilemarksFiletype", { clear = true })
    state.filetype_autocmd = group
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
        group = group,
        pattern = { "filemarks", "Filemarks://*" },
        callback = function(ev)
            -- autocmd events carry no window id; both events fire with the
            -- relevant window current, so let the helpers default to it
            M.configure_comment(ev.buf)
        end,
    })
    vim.api.nvim_create_autocmd("BufWinLeave", {
        group = group,
        pattern = "Filemarks://*",
        callback = function()
            M.clear_comment_match()
        end,
    })
end

return M
