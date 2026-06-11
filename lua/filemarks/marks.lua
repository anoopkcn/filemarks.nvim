-- User-facing mark actions: add, remove, open (jump), list, toggle.
-- Data lives behind the store; path forms behind markpath.

local state = require("filemarks.state")
local markpath = require("filemarks.markpath")
local project = require("filemarks.project")
local store = require("filemarks.store")
local keymaps = require("filemarks.keymaps")
local editor = require("filemarks.ui.editor")

local notify = vim.notify
local log = vim.log.levels

local M = {}

local function prompt_key(prompt)
    local key = vim.fn.input(prompt or "Mark key: ")
    return key ~= "" and key or nil
end

local function detect_project(path_hint)
    local proj = project.detect(path_hint)
    if not proj then
        return nil, "Unable to determine project directory"
    end
    return proj
end

-- Directory context of the current buffer: netrw dir, the buffer's own
-- directory, or the cwd
local function current_dir_context()
    local netrw_dir = vim.b.netrw_curdir
    if type(netrw_dir) == "string" and netrw_dir ~= "" then
        return markpath.normalize(netrw_dir)
    end

    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file and current_file ~= "" then
        local normalized = markpath.normalize(current_file)
        if normalized and markpath.is_directory(normalized) then
            return normalized
        end
        local parent = normalized and vim.fs.dirname(normalized) or nil
        if parent and parent ~= "" then
            return markpath.normalize(parent)
        end
    end

    return markpath.normalize(vim.fn.getcwd())
end

local function focus_buffer_for_path(path)
    local target = markpath.normalize(path)
    if not target then
        return false
    end

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" and markpath.normalize(name) == target then
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    if vim.api.nvim_win_get_buf(win) == bufnr then
                        vim.api.nvim_set_current_win(win)
                        return true
                    end
                end
                local ok = pcall(vim.cmd, "buffer " .. bufnr)
                return ok
            end
        end
    end
    return false
end

local function open_directory(dir_path)
    local dir_open_cmd = state.config.dir_open_cmd
    if dir_open_cmd == nil or dir_open_cmd == "" then
        notify("Filemarks: file explorer not set", log.INFO)
        return
    end

    if type(dir_open_cmd) == "function" then
        local ok, result = pcall(dir_open_cmd, dir_path)
        if not ok then
            notify(string.format("Filemarks: directory handler error: %s", result), log.ERROR)
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
                notify(string.format("Filemarks: invalid dir_open_cmd: %s", formatted), log.ERROR)
                return
            end
            cmd = formatted
        else
            cmd = cmd .. " " .. vim.fn.fnameescape(dir_path)
        end
        local ok, err = pcall(vim.cmd, cmd)
        if not ok then
            notify(string.format("Filemarks: unable to open directory: %s", err), log.ERROR)
        end
        return
    end

    notify("Filemarks: dir_open_cmd must be a string or function", log.ERROR)
end

function M.install_action_keymaps()
    keymaps.install_default_action_keymaps()
end

function M.add(key, file_path)
    key = key or prompt_key("Add mark key: ")
    if not key then
        return
    end
    local input = markpath.normalize(file_path or vim.api.nvim_buf_get_name(0))
    if not input or input == "" then
        notify("Filemarks: unable to determine file path", log.WARN)
        return
    end
    local proj, err = detect_project(input)
    if not proj then
        notify(string.format("Filemarks: %s", err), log.ERROR)
        return
    end
    local mark = markpath.resolve(input, proj)
    if not mark then
        notify("Filemarks: unable to resolve file path", log.ERROR)
        return
    end

    local existing = store.get(proj, key)
    if existing ~= nil then
        local existing_mark = type(existing) == "string" and existing ~= ""
            and markpath.resolve(existing, proj) or nil
        if existing_mark and existing_mark.resolved == mark.resolved then
            notify(string.format("Filemarks: %s already points to %s", key, mark.display), log.INFO)
            return
        end
        local current_display = existing_mark and existing_mark.display
            or markpath.relativize(existing, proj)
        local choice = vim.fn.confirm(
            string.format(
                "Filemarks: %s already points to '%s' replace with '%s'?",
                key,
                current_display,
                mark.display),
            "&Yes\n&No",
            1
        )
        if choice ~= 1 then
            notify("Filemarks: keeping existing mark", log.INFO)
            return
        end
    end

    store.set(proj, key, mark.stored)
    notify(string.format("Filemarks: added %s -> %s", key, mark.display), log.INFO)
end

function M.add_dir(key, dir_path)
    key = key or prompt_key("Add directory mark key: ")
    if not key then
        return
    end
    local resolved_dir = dir_path and markpath.normalize(dir_path) or current_dir_context()
    if not resolved_dir or resolved_dir == "" then
        notify("Filemarks: unable to determine directory path", log.WARN)
        return
    end

    if not markpath.is_directory(resolved_dir) then
        notify(string.format("Filemarks: '%s' is not a directory", dir_path or resolved_dir), log.WARN)
        return
    end

    M.add(key, resolved_dir)
end

function M.remove(key)
    key = key or prompt_key("Remove mark key: ")
    if not key then
        return
    end
    local proj, err = detect_project()
    if not proj then
        notify(string.format("Filemarks: %s", err), log.ERROR)
        return
    end
    if not store.remove(proj, key) then
        notify(string.format("Filemarks: %s not defined for this project", key), log.WARN)
        return
    end
    notify(string.format("Filemarks: removed %s", key), log.INFO)
end

function M.list(opts)
    local proj, err = detect_project()
    if not proj then
        notify(string.format("Filemarks: %s", err), log.ERROR)
        return
    end
    editor.open_editor(proj, store.marks_for(proj), opts)
end

function M.toggle(opts)
    if editor.close_editor() then
        return
    end
    M.list(opts)
end

--- Open a resolved markpath record: directories go through dir_open_cmd,
--- files focus an existing window/buffer or :edit in the current window.
function M.show(mark)
    if mark.is_dir then
        open_directory(mark.resolved)
        return
    end

    if focus_buffer_for_path(mark.resolved) then
        return
    end
    local ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(mark.resolved))
    if not ok then
        notify(string.format("Filemarks: unable to open %s: %s", mark.display, err), log.ERROR)
    end
end

local function open_mark(key)
    if not key or key == "" then
        return
    end
    local proj, err = detect_project()
    if not proj then
        notify(string.format("Filemarks: %s", err), log.ERROR)
        return
    end
    local stored = store.get(proj, key)
    if stored == nil then
        notify(string.format("Filemarks: no file set for mark %s", key), log.INFO)
        return
    end
    if type(stored) ~= "string" or stored == "" then
        notify(string.format("Filemarks: invalid path for %s", key), log.ERROR)
        return
    end
    local mark = markpath.resolve(stored, proj)
    if not mark then
        notify(string.format("Filemarks: unable to resolve %s for project", key), log.ERROR)
        return
    end

    M.show(mark)
end

M.open = open_mark

return M
