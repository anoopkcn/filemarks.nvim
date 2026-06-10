-- A mark's path exists in three forms:
--   stored   - what goes in the storage file (project-relative when possible)
--   resolved - absolute, symlinks resolved; what :edit receives
--   display  - what the list editor shows (stored form, trailing '/' for dirs)
-- M.resolve() is the one place inputs are converted into all three.

local uv = vim.uv or vim.loop

local M = {}

local function is_absolute(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local first = path:sub(1, 1)
    return first == "/" or first == "\\" or path:match("^%a:[/\\]") ~= nil
end

function M.normalize(path)
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

function M.relativize(path, project)
    if type(path) ~= "string" or path == "" or not project or project == "" then
        return path
    end
    if not is_absolute(path) then
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

local function resolve_absolute(input, project)
    if type(input) ~= "string" then
        return nil
    end
    local trimmed = vim.trim(input)
    if trimmed == "" then
        return nil
    end
    if trimmed:sub(1, 1) == "~" then
        trimmed = vim.fn.expand(trimmed)
    elseif not is_absolute(trimmed) then
        if not project or project == "" then
            return nil
        end
        trimmed = vim.fs.joinpath(project, trimmed)
    end
    return M.normalize(trimmed)
end

--- Convert any path input (stored form, user input, absolute, ~-prefixed)
--- into a markpath record, or nil if it cannot be resolved.
--- @return table|nil { resolved, stored, display, is_dir }
function M.resolve(input, project)
    local resolved = resolve_absolute(input, project)
    if not resolved then
        return nil
    end
    local stored = M.relativize(resolved, project)
    local is_dir = M.is_directory(resolved)
    local display = stored
    if is_dir and not vim.endswith(display, "/") then
        display = display .. "/"
    end
    return { resolved = resolved, stored = stored, display = display, is_dir = is_dir }
end

return M
