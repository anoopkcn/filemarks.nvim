local state = require("filemarks.state")
local paths = require("filemarks.paths")
local storage = require("filemarks.storage")
local keymaps = require("filemarks.keymaps")
local editor = require("filemarks.ui.editor")

local M = {}

local function prompt_key(prompt)
    local key = vim.fn.input(prompt or "Mark key: ")
    return key ~= "" and key or nil
end

local function get_marks(path_hint)
    local project = paths.detect_project(path_hint)
    if not project then
        return nil, "Unable to determine project directory"
    end
    local marks = state.data[project]
    if type(marks) ~= "table" then
        marks = {}
        state.data[project] = marks
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
        vim.notify("Filemarks: unable to determine file path", vim.log.levels.WARN)
        return
    end
    local marks, project_or_err = get_marks(resolved_file)
    if not marks then
        vim.notify(string.format("Filemarks: %s", project_or_err or "unknown error"), vim.log.levels.ERROR)
        return
    end
    local project = project_or_err
    local display_path = paths.relativize_path(resolved_file, project)
    local existing_value = marks[key]

    if existing_value and type(existing_value) == "string" and existing_value ~= "" then
        local resolved_existing = paths.resolve_project_path(existing_value, project)
        if resolved_existing == resolved_file then
            vim.notify(string.format("Filemarks: %s already points to %s", key, display_path), vim.log.levels.INFO)
            return
        end
    end

    if existing_value then
        local current_display = paths.relativize_path(existing_value, project)
        local new_display = paths.relativize_path(resolved_file, project)
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
            vim.notify("Filemarks: keeping existing mark", vim.log.levels.INFO)
            return
        end
    end
    local stored_path = paths.relativize_path(resolved_file, project)
    marks[key] = stored_path
    storage.save()
    keymaps.ensure_jump_keymap(key)
    vim.notify(string.format("Filemarks: added %s -> %s", key, display_path), vim.log.levels.INFO)
end

function M.add_dir(key, dir_path)
    storage.load()
    key = key or prompt_key("Add directory mark key: ")
    if not key then
        return
    end
    local target_dir = dir_path
    if not target_dir or target_dir == "" then
        local ok, netrw_dir = pcall(vim.api.nvim_buf_get_var, 0, "netrw_curdir")
        if ok and netrw_dir and netrw_dir ~= "" then
            target_dir = netrw_dir
        else
            local current_file = vim.api.nvim_buf_get_name(0)
            if current_file and current_file ~= "" then
                if paths.is_directory(current_file) then
                    target_dir = current_file
                else
                    target_dir = vim.fn.fnamemodify(current_file, ":p:h")
                end
            else
                target_dir = vim.fn.getcwd()
            end
        end
    end

    local resolved_dir = paths.normalize_path(target_dir)
    if not resolved_dir or resolved_dir == "" then
        vim.notify("Filemarks: unable to determine directory path", vim.log.levels.WARN)
        return
    end

    if not paths.is_directory(resolved_dir) then
        vim.notify(string.format("Filemarks: '%s' is not a directory", target_dir), vim.log.levels.WARN)
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
        vim.notify(string.format("Filemarks: %s", project_or_err or "unknown error"), vim.log.levels.ERROR)
        return
    end
    if not marks[key] then
        vim.notify(string.format("Filemarks: %s not defined for this project", key), vim.log.levels.WARN)
        return
    end
    marks[key] = nil
    if vim.tbl_isempty(marks) then
        state.data[project_or_err] = nil
    end
    storage.save()
    keymaps.rebuild_jump_keymaps()
    vim.notify(string.format("Filemarks: removed %s", key), vim.log.levels.INFO)
end

function M.list(opts)
    storage.load()
    local marks, project_or_err = get_marks()
    if not marks then
        vim.notify(string.format("Filemarks: %s", project_or_err or "unknown error"), vim.log.levels.ERROR)
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
        vim.notify(string.format("Filemarks: %s", project_or_err or "unknown error"), vim.log.levels.ERROR)
        return
    end
    local project = project_or_err
    if not marks[key] then
        vim.notify(string.format("Filemarks: no file set for mark %s", key), vim.log.levels.INFO)
        return
    end
    local path = marks[key]
    if not path or path == "" then
        vim.notify(string.format("Filemarks: invalid path for %s", key), vim.log.levels.ERROR)
        return
    end
    local resolved = paths.resolve_project_path(path, project)
    if not resolved then
        vim.notify(string.format("Filemarks: unable to resolve %s for project", key), vim.log.levels.ERROR)
        return
    end

    if paths.is_directory(resolved) then
        vim.cmd("Explore " .. vim.fn.fnameescape(resolved))
        return
    end

    if paths.focus_buffer_for_path(resolved) then
        return
    end
    local cwd = paths.normalize_path(vim.fn.getcwd())
    local edit_arg = resolved
    if cwd == project and type(path) == "string" and path ~= "" and not paths.is_absolute_path(path) then
        edit_arg = path
    end
    vim.cmd("edit " .. vim.fn.fnameescape(edit_arg))
end

M.open = open_mark

keymaps.set_open_handler(open_mark)

return M
