-- A project is the namespace marks live under: the nearest root-marker
-- directory, falling back to the cwd. Detection results are cached
-- per-buffer; this module owns the cache and its invalidation.

local state = require("filemarks.state")
local markpath = require("filemarks.markpath")

local M = {}

local function ensure_cache_invalidation()
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
    -- The cwd fallback below makes every buffer's cached project suspect
    -- once the working directory changes
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

function M.detect(path)
    ensure_cache_invalidation()
    local target = path and vim.fn.fnamemodify(path, ":p:h") or nil
    if not path then
        local cached = vim.b.filemarks_project_cached
        if type(cached) == "string" and cached ~= "" then
            return cached
        end
    end
    local ok, root = pcall(vim.fs.root, target or 0, state.config.project_markers)
    local resolved = ok and root and markpath.normalize(root) or markpath.normalize(vim.fn.getcwd())
    if not path and type(resolved) == "string" and resolved ~= "" then
        vim.b.filemarks_project_cached = resolved
    end
    return resolved
end

return M
