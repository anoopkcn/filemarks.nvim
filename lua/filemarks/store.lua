-- The mark store: the only module that touches mark data. Every mutation
-- goes through set/remove/replace, which persist atomically and keep the
-- jump keymaps projected from the data. Callers never see the storage
-- format, the dirty flag, or the keymap sync.

local state = require("filemarks.state")
local markpath = require("filemarks.markpath")
local keymaps = require("filemarks.keymaps")

local uv = vim.uv or vim.loop

local notify = vim.notify
local log = vim.log.levels

local FILE_READ_MODE = 420 -- octal 0644

local M = {}

-- All persistence state is module-local; reconfiguring the plugin
-- never resets it (see config.lua)
local data = {}
local dirty = false
local loaded = false
local loaded_path = nil
local load_failed = false

local function ensure_storage_dir()
    local dir = vim.fs.dirname(state.config.storage_path)
    if dir and dir ~= "" then
        vim.fn.mkdir(dir, "p")
    end
end

local function write_json(encoded)
    local path = state.config.storage_path
    local tmp = path .. ".tmp"
    local ok_write, err_write = pcall(vim.fn.writefile, { encoded }, tmp)
    if not ok_write then
        notify(string.format("Filemarks: failed to save (write) - %s", err_write), log.ERROR)
        dirty = true
        return
    end
    local ok_pcall, rc, err_rename = pcall(os.rename, tmp, path)
    if not ok_pcall or not rc then
        notify(
            string.format("Filemarks: failed to save (rename) - %s", err_rename or rc or "unknown"),
            log.ERROR
        )
        pcall(os.remove, tmp)
        dirty = true
    end
end

local function save()
    if load_failed then
        notify(
            string.format("Filemarks: not saving - %s could not be parsed; fix or remove it and restart",
                state.config.storage_path),
            log.ERROR
        )
        return
    end
    if not dirty then
        return
    end
    ensure_storage_dir()
    local ok, encoded = pcall(vim.json.encode, data)
    if not ok then
        notify(string.format("Filemarks: failed to encode filemarks - %s", encoded), log.ERROR)
        return
    end
    dirty = false
    write_json(encoded)
end

-- Rewrite marks into canonical stored form (project-relative when possible)
local function canonicalize(project, marks)
    local updated = false
    for key, stored in pairs(marks) do
        if type(stored) == "string" and stored ~= "" then
            local mark = markpath.resolve(stored, project)
            if mark and mark.stored ~= stored then
                marks[key] = mark.stored
                updated = true
            end
        end
    end
    return updated
end

local function all_keys()
    local keys = {}
    for _, marks in pairs(data) do
        if type(marks) == "table" then
            for key in pairs(marks) do
                keys[key] = true
            end
        end
    end
    return keys
end

local function load()
    local path = state.config.storage_path
    if loaded and loaded_path == path then
        return
    end
    loaded = true
    loaded_path = path
    load_failed = false
    dirty = false
    data = {}
    local fd = uv.fs_open(path, "r", FILE_READ_MODE)
    if fd then
        local stat = uv.fs_fstat(fd)
        if stat and stat.size > 0 then
            local content = uv.fs_read(fd, stat.size, 0)
            if type(content) == "string" and #content > 0 then
                local ok, decoded = pcall(vim.json.decode, content)
                if ok and type(decoded) == "table" then
                    data = decoded
                else
                    uv.fs_close(fd)
                    local backup = path .. ".corrupt"
                    local ok_rename, renamed = pcall(os.rename, path, backup)
                    if ok_rename and renamed then
                        notify(
                            string.format("Filemarks: failed to parse %s - moved it to %s and started fresh",
                                path, backup),
                            log.ERROR
                        )
                    else
                        load_failed = true
                        notify(
                            string.format("Filemarks: failed to parse %s - saving disabled to avoid overwriting it",
                                path),
                            log.ERROR
                        )
                    end
                    return
                end
            end
        end
        uv.fs_close(fd)
    end
    local needs_save = false
    for project, marks in pairs(data) do
        if type(marks) == "table" then
            if canonicalize(project, marks) then
                needs_save = true
            end
            for key in pairs(marks) do
                keymaps.ensure_jump_keymap(key, { silent = true })
            end
        end
    end
    if needs_save then
        dirty = true
        save()
    end
end

function M.load()
    load()
end

--- Marks for a project, as a copy - mutations only happen through the store.
function M.marks_for(project)
    load()
    local marks = data[project]
    return type(marks) == "table" and vim.deepcopy(marks) or {}
end

function M.get(project, key)
    load()
    local marks = data[project]
    if type(marks) ~= "table" then
        return nil
    end
    return marks[key]
end

function M.set(project, key, stored_path)
    load()
    local marks = data[project]
    if type(marks) ~= "table" then
        marks = {}
        data[project] = marks
    end
    marks[key] = stored_path
    dirty = true
    save()
    keymaps.ensure_jump_keymap(key)
end

--- Returns false if the key was not set for the project.
function M.remove(project, key)
    load()
    local marks = data[project]
    if type(marks) ~= "table" or marks[key] == nil then
        return false
    end
    marks[key] = nil
    if next(marks) == nil then
        data[project] = nil
    end
    dirty = true
    save()
    keymaps.rebuild_jump_keymaps(all_keys())
    return true
end

--- Replace a project's marks wholesale (empty/nil removes the project).
function M.replace(project, marks)
    load()
    if type(marks) == "table" and next(marks) then
        data[project] = vim.deepcopy(marks)
    else
        data[project] = nil
    end
    dirty = true
    save()
    keymaps.rebuild_jump_keymaps(all_keys())
end

--- Re-project jump keymaps from the data (used after reconfiguration
--- clears all keymaps). No-op before the first load.
function M.sync_jump_keymaps(opts)
    if not loaded then
        return
    end
    keymaps.rebuild_jump_keymaps(all_keys(), opts)
end

return M
