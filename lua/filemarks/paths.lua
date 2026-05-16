local state = require("filemarks.state")

local uv = vim.uv or vim.loop

local M = {}

function M.is_absolute_path(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local first = path:sub(1, 1)
    return first == "/" or first == "\\" or path:match("^%a:[/\\]") ~= nil
end

function M.relativize_path(path, project)
    if type(path) ~= "string" or path == "" or not project or project == "" then
        return path
    end
    if not M.is_absolute_path(path) then
        return path
    end

    if vim.startswith(path, project) then
        local boundary_idx = #project + 1
        local boundary = path:sub(boundary_idx, boundary_idx)
        if boundary == "" then
            return "."
        end
        if boundary == "/" or boundary == "\\" then
            local rel = path:sub(boundary_idx + 1)
            return rel ~= "" and rel or "."
        end
    end

    local ok, rel = pcall(vim.fs.relpath, project, path)
    if ok and rel and not vim.startswith(rel, "..") then
        return rel
    end
    return path
end

function M.normalize_path(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local ok, resolved = pcall(uv.fs_realpath, path)
    if ok and type(resolved) == "string" then
        return vim.fs.normalize(resolved)
    end
    return vim.fs.normalize(path)
end

function M.is_directory(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local stat = uv.fs_stat(path)
    return stat and stat.type == "directory"
end

function M.current_dir_context(bufnr)
    local target_buf = bufnr or 0
    if target_buf ~= 0 and not vim.api.nvim_buf_is_valid(target_buf) then
        return nil
    end
    local netrw_dir = vim.b[target_buf].netrw_curdir
    if type(netrw_dir) == "string" and netrw_dir ~= "" then
        return M.normalize_path(netrw_dir)
    end

    local current_file = vim.api.nvim_buf_get_name(target_buf)
    if current_file and current_file ~= "" then
        local normalized = M.normalize_path(current_file)
        if normalized and M.is_directory(normalized) then
            return normalized
        end
        local parent = normalized and vim.fs.dirname(normalized) or nil
        if parent and parent ~= "" then
            return M.normalize_path(parent)
        end
    end

    return M.normalize_path(vim.fn.getcwd())
end

function M.focus_buffer_for_path(path)
    local target = M.normalize_path(path)
    if not target then
        return false
    end

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" and M.normalize_path(name) == target then
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    if vim.api.nvim_win_get_buf(win) == bufnr then
                        vim.api.nvim_set_current_win(win)
                        return true
                    end
                end
                vim.cmd("buffer " .. bufnr)
                return true
            end
        end
    end
    return false
end

function M.detect_project(path)
    local target = path and vim.fn.fnamemodify(path, ":p:h") or nil
    if not path then
        local cached = vim.b.filemarks_project_cached
        if type(cached) == "string" and cached ~= "" then
            return cached
        end
    end
    local ok, root = pcall(vim.fs.root, target or 0, state.config.project_markers)
    local resolved = ok and root and M.normalize_path(root) or M.normalize_path(vim.fn.getcwd())
    if not path and type(resolved) == "string" and resolved ~= "" then
        vim.b.filemarks_project_cached = resolved
    end
    return resolved
end

function M.resolve_project_path(path, project)
    if type(path) ~= "string" then
        return nil
    end
    local trimmed = vim.trim(path)
    if trimmed == "" then
        return nil
    end
    if trimmed:sub(1, 1) == "~" then
        trimmed = vim.fn.expand(trimmed)
    elseif not M.is_absolute_path(trimmed) then
        local base = project or M.detect_project()
        if not base then
            return nil
        end
        trimmed = vim.fs.joinpath(base, trimmed)
    end
    return M.normalize_path(trimmed)
end

function M.resolve_mark_paths(path, project)
    local resolved = M.resolve_project_path(path, project)
    if not resolved then
        return nil
    end
    local stored = M.relativize_path(resolved, project)
    local is_dir = M.is_directory(resolved)
    local display = stored
    if is_dir and not vim.endswith(display, "/") then
        display = display .. "/"
    end
    return resolved, stored, display, is_dir
end

return M
