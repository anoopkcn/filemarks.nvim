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

local function ensure_project_cache_invalidation()
    if state.project_cache_autocmd then
        return
    end
    local group = vim.api.nvim_create_augroup("FilemarksProjectCache", { clear = true })
    state.project_cache_autocmd = group
    vim.api.nvim_create_autocmd({ "BufFilePost", "BufNewFile" }, {
        group = group,
        callback = function(ev)
            vim.b[ev.buf].filemarks_project_cached = nil
        end,
    })
    -- The cwd fallback in detect_project makes every buffer's cached project
    -- suspect once the working directory changes
    vim.api.nvim_create_autocmd("DirChanged", {
        group = group,
        callback = function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) then
                    vim.b[buf].filemarks_project_cached = nil
                end
            end
        end,
    })
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
    local path = state.config.storage_path
    local tmp = path .. ".tmp"
    local ok_write, err_write = pcall(vim.fn.writefile, { encoded }, tmp)
    if not ok_write then
        notify(string.format("Filemarks: failed to save (write) - %s", err_write), log.ERROR)
        state.dirty = true
        return
    end
    local ok_pcall, rc, err_rename = pcall(os.rename, tmp, path)
    if not ok_pcall or not rc then
        notify(
            string.format("Filemarks: failed to save (rename) - %s", err_rename or rc or "unknown"),
            log.ERROR
        )
        pcall(os.remove, tmp)
        state.dirty = true
    end
end

function M.save()
    if state.load_failed then
        notify(
            string.format("Filemarks: not saving - %s could not be parsed; fix or remove it and restart",
                state.config.storage_path),
            log.ERROR
        )
        return
    end
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
    ensure_project_cache_invalidation()
    local fd = uv.fs_open(path, "r", FILE_READ_MODE)
    if fd then
        local stat = uv.fs_fstat(fd)
        if stat and stat.size > 0 then
            local content = uv.fs_read(fd, stat.size, 0)
            if type(content) == "string" and #content > 0 then
                local ok, decoded = pcall(vim.json.decode, content)
                if ok and type(decoded) == "table" then
                    state.data = decoded
                else
                    uv.fs_close(fd)
                    local backup = path .. ".corrupt"
                    local ok_rename, renamed = pcall(os.rename, path, backup)
                    if ok_rename and renamed then
                        notify(
                            string.format("Filemarks: failed to parse %s - moved it to %s and started fresh", path,
                                backup),
                            log.ERROR
                        )
                    else
                        state.load_failed = true
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
    for project, marks in pairs(state.data) do
        if type(marks) == "table" then
            if canonicalize_project_marks(project, marks) then
                needs_save = true
            end
            for key in pairs(marks) do
                keymaps.ensure_jump_keymap(key, { silent = true })
            end
        end
    end
    if needs_save then
        M.mark_dirty()
        M.save()
    end
end

return M
