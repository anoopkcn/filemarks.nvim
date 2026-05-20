local state = require("filemarks.state")
local paths = require("filemarks.paths")
local storage = require("filemarks.storage")
local keymaps = require("filemarks.keymaps")

local notify = vim.notify
local log = vim.log.levels

local M = {}

local function ensure_comment_match(win)
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

local function clear_comment_match(win)
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

local function configure_comment(buf, win)
    vim.api.nvim_set_option_value("commentstring", "# %s", { buf = buf })
    ensure_comment_match(win)
end

local function editor_has_unsaved_changes(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return false
    end
    return vim.api.nvim_get_option_value("modified", { buf = buf }) == true
end

local function generate_editor_lines(project, marks)
    local lines = {}

    if state.config.show_help then
        vim.list_extend(lines, {
            string.format("# Filemarks for %s", project),
            "# Format: <key> -> <path>. Directories should have a trailing '/'",
            "",
        })
    end

    local keys = vim.tbl_keys(marks or {})
    table.sort(keys)

    local mark_lines = vim.tbl_map(function(key)
        local stored_path = marks[key]
        local _, _, display = paths.resolve_mark_paths(stored_path, project)
        local display_path = display or paths.relativize_path(stored_path, project)
        return string.format("%s -> %s", key, display_path or "")
    end, keys)

    vim.list_extend(lines, mark_lines)
    return lines
end

local function parse_editor_buffer(buf, project)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local parsed = {}
    for idx, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "#") then
            local key, path = trimmed:match("^(%S+)%s*%->%s*(.+)$")
            if not key or not path then
                return nil, string.format("Line %d is invalid. Expected '<key> -> <path>'", idx)
            end
            if parsed[key] then
                return nil, string.format("Duplicate key '%s' detected on line %d", key, idx)
            end
            local resolved, stored = paths.resolve_mark_paths(path, project)
            if not resolved then
                return nil, string.format("Could not resolve path on line %d", idx)
            end
            parsed[key] = stored
        end
    end
    return parsed
end

local function setup_filemarks_buffer_autocmds(buf)
    local augroup = vim.api.nvim_create_augroup("FilemarksBuffer_" .. buf, { clear = true })

    vim.api.nvim_create_autocmd("BufUnload", {
        group = augroup,
        buffer = buf,
        callback = function()
            if vim.api.nvim_buf_is_valid(buf) then
                if editor_has_unsaved_changes(buf) then
                    vim.notify("Filemarks: buffer closed without saving - changes discarded", vim.log.levels.WARN)
                end
                vim.api.nvim_set_option_value("modified", false, { buf = buf })
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        group = augroup,
        buffer = buf,
        callback = function()
            local project_var = vim.b[buf].filemarks_project
            if not project_var then
                notify("Filemarks: unable to determine project for editor buffer", log.ERROR)
                return
            end
            local parsed, parse_err = parse_editor_buffer(buf, project_var)
            if not parsed then
                notify(string.format("Filemarks: %s", parse_err), log.ERROR)
                return
            end
            if next(parsed) then
                state.data[project_var] = parsed
            else
                state.data[project_var] = nil
            end
            storage.mark_dirty()
            storage.save()
            keymaps.rebuild_jump_keymaps()
            vim.api.nvim_set_option_value("modified", false, { buf = buf })
            notify("Filemarks: saved changes", log.INFO)
        end,
    })
end

function M.open_editor(project, marks, cmd_opts)
    M.install_filetype_support()
    local target_name = string.format("Filemarks://%s", project)
    local existing, existing_win = nil, nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == target_name then
            existing, existing_win = buf, win
            break
        end
    end
    if not existing then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == target_name then
                existing = buf
                break
            end
        end
    end
    local mods = cmd_opts and cmd_opts.mods or ""
    local use_mods = type(mods) == "string" and mods ~= ""

    if existing_win then
        vim.api.nvim_set_current_win(existing_win)
        ensure_comment_match(existing_win)
        return
    end

    local target_win = nil
    if use_mods then
        local ok = pcall(vim.cmd, mods .. " new")
        if ok and vim.api.nvim_win_is_valid(0) then
            target_win = vim.api.nvim_get_current_win()
        end
    end

    if not target_win then
        local open_cmd = state.config.list_open_cmd
        if type(open_cmd) == "function" then
            local ok, result = pcall(open_cmd)
            if ok and type(result) == "number" and vim.api.nvim_win_is_valid(result) then
                target_win = result
            else
                target_win = vim.api.nvim_get_current_win()
            end
        elseif type(open_cmd) == "string" and open_cmd ~= "" then
            pcall(vim.cmd, open_cmd)
            target_win = vim.api.nvim_get_current_win()
        end
    end

    if not target_win or not vim.api.nvim_win_is_valid(target_win) then
        target_win = vim.api.nvim_get_current_win()
    end

    if existing then
        vim.api.nvim_win_set_buf(target_win, existing)
        configure_comment(existing, target_win)
        return
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(target_win, buf)
    vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "filemarks", { buf = buf })
    vim.api.nvim_buf_set_name(buf, target_name)
    vim.b[buf].filemarks_project = project
    local lines = generate_editor_lines(project, marks)
    if vim.tbl_isempty(lines) then
        lines = { "" }
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    configure_comment(buf, target_win)

    if marks and not vim.tbl_isempty(marks) then
        for i, line in ipairs(lines) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" and not vim.startswith(trimmed, "#") then
                vim.api.nvim_win_set_cursor(target_win, { i, 0 })
                break
            end
        end
    end

    setup_filemarks_buffer_autocmds(buf)
    vim.b[buf].filemarks_initialized = true
end

function M.close_editor()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_loaded(buf) then
            local name = vim.api.nvim_buf_get_name(buf)
            if name and name:match("^Filemarks://") then
                local ok, err = pcall(vim.api.nvim_win_close, win, false)
                if not ok then
                    notify(string.format("Filemarks: unable to close window: %s", err), log.WARN)
                end
                return true
            end
        end
    end
    return false
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
            configure_comment(ev.buf, ev.win)
        end,
    })
    vim.api.nvim_create_autocmd("BufWinLeave", {
        group = group,
        pattern = "Filemarks://*",
        callback = function(ev)
            clear_comment_match(ev.win)
        end,
    })
end

return M
