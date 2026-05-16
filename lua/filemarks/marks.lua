local state = require("filemarks.state")
local paths = require("filemarks.paths")
local storage = require("filemarks.storage")
local keymaps = require("filemarks.keymaps")
local editor = require("filemarks.ui.editor")

local notify = vim.notify
local log = vim.log.levels

local M = {}

local function prompt_key(prompt)
    local key = vim.fn.input(prompt or "Mark key: ")
    return key ~= "" and key or nil
end

local function resolve_mark_paths(path, project)
    local resolved, stored, display, is_dir = paths.resolve_mark_paths(path, project)
    if not resolved then
        return nil
    end
    return {
        resolved = resolved,
        stored = stored,
        display = display,
        is_dir = is_dir,
    }
end

local function open_directory(dir_path)
    local dir_open_cmd = state.config.dir_open_cmd
    if dir_open_cmd == nil or dir_open_cmd == "" then
        vim.notify("Filemarks: file explorer not set", vim.log.levels.INFO)
        return
    end

    if type(dir_open_cmd) == "function" then
        local ok, result = pcall(dir_open_cmd, dir_path)
        if not ok then
            vim.notify(string.format("Filemarks: directory handler error: %s", result), vim.log.levels.ERROR)
            return
        end
        if type(result) == "number" and vim.api.nvim_win_is_valid(result) then
            vim.api.nvim_set_current_win(result)
        end
        return
    end

    if type(dir_open_cmd) == "string" then
        local cmd = dir_open_cmd
        if cmd:find("%%s") then
            local ok, formatted = pcall(string.format, cmd, vim.fn.fnameescape(dir_path))
            if not ok then
                vim.notify(string.format("Filemarks: invalid dir_open_cmd: %s", formatted), vim.log.levels.ERROR)
                return
            end
            cmd = formatted
        else
            cmd = cmd .. " " .. vim.fn.fnameescape(dir_path)
        end
        local ok, err = pcall(vim.cmd, cmd)
        if not ok then
            vim.notify(string.format("Filemarks: unable to open directory: %s", err), vim.log.levels.ERROR)
        end
        return
    end

    vim.notify("Filemarks: dir_open_cmd must be a string or function", vim.log.levels.ERROR)
end

local function get_marks(path_hint, create)
    local project = paths.detect_project(path_hint)
    if not project then
        return nil, "Unable to determine project directory"
    end
    local marks = state.data[project]
    if type(marks) ~= "table" then
        marks = {}
        if create then
            state.data[project] = marks
        end
    end
    return marks, project
end

local ACTION_MAPPINGS = {
    { key = "a", desc = "Add filemark", fn = function() M.add() end },
    { key = "d", desc = "Add directory mark", fn = function() M.add_dir() end },
    { key = "r", desc = "Remove filemark", fn = function() M.remove() end },
    { key = "l", desc = "Edit filemarks", fn = function() M.list() end },
}

function M.install_action_keymaps()
    keymaps.install_action_keymaps(ACTION_MAPPINGS)
end

function M.add(key, file_path)
    storage.load()
    key = key or prompt_key("Add mark key: ")
    if not key then
        return
    end
    local resolved_file = paths.normalize_path(file_path or vim.api.nvim_buf_get_name(0))
    if not resolved_file or resolved_file == "" then
        notify("Filemarks: unable to determine file path", log.WARN)
        return
    end
    local marks, project_or_err = get_marks(resolved_file, true)
    if not marks then
        notify(string.format("Filemarks: %s", project_or_err or "unknown error"), log.ERROR)
        return
    end
    local project = project_or_err
    local resolved_paths = resolve_mark_paths(resolved_file, project)
    if not resolved_paths then
        notify("Filemarks: unable to resolve file path", log.ERROR)
        return
    end
    local display_path = resolved_paths.display
    local existing_value = marks[key]

    if existing_value and type(existing_value) == "string" and existing_value ~= "" then
        local resolved_existing = paths.resolve_project_path(existing_value, project)
        if resolved_existing == resolved_paths.resolved then
            notify(string.format("Filemarks: %s already points to %s", key, display_path), log.INFO)
            return
        end
    end

    if existing_value then
        local current_display = paths.relativize_path(existing_value, project)
        local new_display = resolved_paths.display
        local choice = vim.fn.confirm(
            string.format(
                "Filemarks: %s already points to '%s' replace with '%s'?",
                key,
                current_display,
                new_display),
            "&Yes\n&No",
            1
        )
        if choice ~= 1 then
            notify("Filemarks: keeping existing mark", log.INFO)
            return
        end
    end

    marks[key] = resolved_paths.stored
    storage.mark_dirty()
    storage.save()
    keymaps.ensure_jump_keymap(key)
    notify(string.format("Filemarks: added %s -> %s", key, display_path), log.INFO)
end

function M.add_dir(key, dir_path)
    storage.load()
    key = key or prompt_key("Add directory mark key: ")
    if not key then
        return
    end
    local resolved_dir = dir_path and paths.normalize_path(dir_path) or paths.current_dir_context()
    if not resolved_dir or resolved_dir == "" then
        notify("Filemarks: unable to determine directory path", log.WARN)
        return
    end

    if not paths.is_directory(resolved_dir) then
        notify(string.format("Filemarks: '%s' is not a directory", dir_path or resolved_dir), log.WARN)
        return
    end

    M.add(key, resolved_dir)
end

function M.remove(key)
    storage.load()
    key = key or prompt_key("Remove mark key: ")
    if not key then
        return
    end
    local marks, project_or_err = get_marks()
    if not marks then
        notify(string.format("Filemarks: %s", project_or_err or "unknown error"), log.ERROR)
        return
    end
    if not marks[key] then
        notify(string.format("Filemarks: %s not defined for this project", key), log.WARN)
        return
    end
    marks[key] = nil
    if vim.tbl_isempty(marks) then
        state.data[project_or_err] = nil
    end
    storage.mark_dirty()
    storage.save()
    keymaps.rebuild_jump_keymaps()
    notify(string.format("Filemarks: removed %s", key), log.INFO)
end

function M.list(opts)
    storage.load()
    local marks, project_or_err = get_marks()
    if not marks then
        notify(string.format("Filemarks: %s", project_or_err or "unknown error"), log.ERROR)
        return
    end
    editor.open_editor(project_or_err, marks, opts)
end

local function open_mark(key)
    storage.load()
    if not key or key == "" then
        return
    end
    local marks, project_or_err = get_marks()
    if not marks then
        notify(string.format("Filemarks: %s", project_or_err or "unknown error"), log.ERROR)
        return
    end
    local project = project_or_err
    if not marks[key] then
        notify(string.format("Filemarks: no file set for mark %s", key), log.INFO)
        return
    end
    local path = marks[key]
    if not path or path == "" then
        notify(string.format("Filemarks: invalid path for %s", key), log.ERROR)
        return
    end
    local resolved_paths = resolve_mark_paths(path, project)
    if not resolved_paths then
        notify(string.format("Filemarks: unable to resolve %s for project", key), log.ERROR)
        return
    end

    if resolved_paths.is_dir then
        open_directory(resolved_paths.resolved)
        return
    end

    if paths.focus_buffer_for_path(resolved_paths.resolved) then
        return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(resolved_paths.resolved))
end

M.open = open_mark

keymaps.set_open_handler(open_mark)

return M
