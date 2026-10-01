-- A mark's path exists in three forms:
--   stored   - what goes in the storage file (project-relative when possible)
--   resolved - absolute, symlinks resolved; what :edit receives
--   display  - what the list editor shows (stored form, trailing '/' for dirs)
-- M.resolve() is the one place inputs are converted into all three.

local uv = vim.uv

local M = {}

local function is_absolute(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local first = path:sub(1, 1)
    return first == "/" or first == "\\" or path:match("^%a:[/\\]") ~= nil
end

-- Path after a URI scheme (oil:///abs/path, or oil:/abs/path once slashes
-- are collapsed), or nil. Scheme needs 2+ chars so Windows drive letters
-- (C:/) are not mistaken for one.
local function after_scheme(path)
    return path:match("^%a[%w+.-]+://(.*)") or path:match("^%a[%w+.-]+:(/.*)")
end

-- Buffer names from plugins like oil.nvim carry a URI scheme; marks always
-- point at real paths, so strip it - but only when the rest exists on disk.
-- term://~/x//123:/bin/zsh or fugitive:///repo/.git//<sha>/f keep their
-- scheme and are rejected by M.is_uri().
local function strip_scheme(path)
    local rest = after_scheme(path)
    if rest and rest ~= "" and uv.fs_stat(rest) then
        return rest
    end
    return path
end

--- True if `path` is a URI that does not name a real file or directory.
function M.is_uri(path)
    return type(path) == "string" and after_scheme(strip_scheme(path)) ~= nil
end

function M.normalize(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    path = strip_scheme(path)
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
    local trimmed = strip_scheme(vim.trim(input))
    if trimmed == "" or M.is_uri(trimmed) then
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
