local state = require("filemarks.state")
local paths = require("filemarks.paths")
local keymaps = require("filemarks.keymaps")

local uv = vim.uv or vim.loop

local notify = vim.notify
local log = vim.log.levels

local FILE_READ_MODE = 420 -- octal 0644

local M = {}

local function ensure_storage_dir()
    local dir = vim.fs.dirname(state.config.storage_path)
    if dir and dir ~= "" then
        vim.fn.mkdir(dir, "p")
    end
end

local function canonicalize_project_marks(project, marks)
    if not project or type(marks) ~= "table" then
        return false
    end
    local updated = false
    for key, stored in pairs(marks) do
        if type(stored) == "string" and stored ~= "" then
            local resolved = paths.resolve_project_path(stored, project)
            if resolved then
                local storage_path = paths.relativize_path(resolved, project)
                if storage_path ~= stored then
                    marks[key] = storage_path
                    updated = true
                end
            end
        end
    end
    return updated
end

function M.mark_dirty()
    state.dirty = true
end

local function write_json(encoded)
    local ok, err = pcall(vim.fn.writefile, { encoded }, state.config.storage_path)
    if not ok then
        notify(string.format("Filemarks: failed to save - %s", err), log.ERROR)
        state.dirty = true
    end
end

function M.save()
    if not state.dirty then
        return
    end
    ensure_storage_dir()
    local ok, encoded = pcall(vim.json.encode, state.data)
    if not ok then
        notify(string.format("Filemarks: failed to encode filemarks - %s", encoded), log.ERROR)
        state.dirty = true
        return
    end
    state.dirty = false
    write_json(encoded)
end

function M.load()
    local path = state.config.storage_path
    if state.loaded and state.loaded_path == path then
        return
    end
    state.loaded = true
    state.loaded_path = path
    local fd = uv.fs_open(path, "r", FILE_READ_MODE)
    if fd then
        local stat = uv.fs_fstat(fd)
        if stat and stat.size > 0 then
            local content = uv.fs_read(fd, stat.size, 0)
            if type(content) == "string" and #content > 0 then
                local ok, decoded = pcall(vim.json.decode, content)
                if ok and type(decoded) == "table" then
                    state.data = decoded
                end
            end
        end
        uv.fs_close(fd)
    end
    local needs_save = false
    for project, marks in pairs(state.data) do
        if type(marks) == "table" then
            if canonicalize_project_marks(project, marks) then
                needs_save = true
            end
            for key in pairs(marks) do
                keymaps.ensure_jump_keymap(key)
            end
        end
    end
    if needs_save then
        M.mark_dirty()
        M.save()
    end
end

return M
