-- LICENSE: MIT
-- by @anoopkcn
-- https://github.com/anoopkcn/dotfiles/blob/main/nvim/lua/filemarks/init.lua
-- Description: A Neovim plugin to manage persistent marks for files and directories per project.

local M = {}

local uv = vim.uv or vim.loop

local default_config = {
    goto_prefix = "<leader>m",
    action_prefix = "<leader>M",
    storage_path = vim.fn.stdpath("state") .. "/filemarks.json",
    project_markers = { ".git", ".hg", ".svn" },
}

local state = {
    config = vim.deepcopy(default_config),
    data = {},
    keymaps = {},
    action_keymaps = {},
    loaded = false,
    commands_installed = false,
    filetype_autocmd = nil,
}

local comment_ns = vim.api.nvim_create_namespace("filemarks_comments")
local comment_watchers = {}

-- Check if path is absolute (Unix: /, Windows: \ or C:\)
local function is_absolute_path(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local first = path:sub(1, 1)
    return first == "/" or first == "\\" or path:match("^%a:[/\\]") ~= nil
end

local function relativize_path(path, project)
    if type(path) ~= "string" or path == "" or not project or project == "" then
        return path
    end
    if not is_absolute_path(path) then
        return path
    end

    -- Check if path is within project directory
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

    local ok, rel = pcall(vim.fs.relpath, path, project)
    if ok and rel and not vim.startswith(rel, "..") then
        return rel
    end
    return path
end

local function highlight_comments(buf, start_line, end_line)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local total_lines = vim.api.nvim_buf_line_count(buf)
    start_line = math.max(start_line or 0, 0)
    end_line = math.max(end_line or total_lines, start_line)

    vim.api.nvim_buf_clear_namespace(buf, comment_ns, start_line, end_line)
    local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
    for idx, line in ipairs(lines) do
        local start_col = line:find("#")
        if start_col and line:sub(1, start_col - 1):match("^%s*$") then
            local row = start_line + idx - 1
            vim.highlight.range(
                buf,
                comment_ns,
                "Comment",
                { row, start_col - 1 },
                { row, #line },
                { inclusive = true }
            )
        end
    end
end

local function attach_comment_highlighter(buf)
    if comment_watchers[buf] then
        return
    end
    comment_watchers[buf] = true
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = function(_, b, _, first, _, new_last)
            highlight_comments(b, first, new_last)
        end,
        on_detach = function(_, b)
            comment_watchers[b] = nil
        end,
    })
end

local function normalize_path(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local ok, resolved = pcall(uv.fs_realpath, path)
    if ok and type(resolved) == "string" then
        return vim.fs.normalize(resolved)
    end
    return vim.fs.normalize(path)
end

local function is_directory(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local stat = uv.fs_stat(path)
    return stat and stat.type == "directory"
end

local function focus_buffer_for_path(path)
    local target = normalize_path(path)
    if not target then
        return false
    end

    local bufnr = vim.fn.bufnr(target)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        -- Check if buffer is visible in a window
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
                vim.api.nvim_set_current_win(win)
                return true
            end
        end
        -- Buffer exists but not visible - switch to it
        vim.api.nvim_cmd({ cmd = "buffer", args = { tostring(bufnr) } }, {})
        return true
    end
    return false
end

local function detect_project(path)
    local target = path and vim.fn.fnamemodify(path, ":p:h") or nil
    local ok, root = pcall(vim.fs.root, target or 0, state.config.project_markers)
    return ok and root and normalize_path(root) or normalize_path(vim.fn.getcwd())
end

local function resolve_project_path(path, project)
    if type(path) ~= "string" then
        return nil
    end
    local trimmed = vim.trim(path)
    if trimmed == "" then
        return nil
    end
    if trimmed:sub(1, 1) == "~" then
        trimmed = vim.fn.expand(trimmed)
    elseif not is_absolute_path(trimmed) then
        local base = project or detect_project()
        if not base then
            return nil
        end
        trimmed = vim.fs.joinpath(base, trimmed)
    end
    return normalize_path(trimmed)
end

local function canonicalize_project_marks(project, marks)
    if not project or type(marks) ~= "table" then
        return false
    end
    local updated = false
    for key, stored in pairs(marks) do
        if type(stored) == "string" and stored ~= "" then
            local resolved = resolve_project_path(stored, project)
            if resolved then
                local storage_path = relativize_path(resolved, project)
                if storage_path ~= stored then
                    marks[key] = storage_path
                    updated = true
                end
            end
        end
    end
    return updated
end

local function get_marks(path_hint)
    local project = detect_project(path_hint)
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

local function key_in_use(key)
    for _, marks in pairs(state.data) do
        if marks[key] then
            return true
        end
    end
    return false
end

local function clear_keymap(key)
    local lhs = state.keymaps[key]
    if lhs then
        pcall(vim.keymap.del, "n", lhs)
        state.keymaps[key] = nil
    end
end

local function ensure_keymap(key)
    if state.keymaps[key] or not state.config.goto_prefix or state.config.goto_prefix == "" then
        return
    end
    local lhs = state.config.goto_prefix .. key
    vim.keymap.set("n", lhs, function()
        M.open(key)
    end, { desc = string.format("Filemarks: jump to %s", key) })
    state.keymaps[key] = lhs
end

local function rebuild_jump_keymaps()
    -- Collect all keys that should exist
    local should_exist = {}
    for _, marks in pairs(state.data) do
        for key in pairs(marks) do
            should_exist[key] = true
        end
    end

    -- Remove keymaps that shouldn't exist
    for key in pairs(state.keymaps) do
        if not should_exist[key] then
            clear_keymap(key)
        end
    end

    -- Ensure keymaps that should exist
    for key in pairs(should_exist) do
        ensure_keymap(key)
    end
end

local function ensure_storage_dir()
    local dir = vim.fn.fnamemodify(state.config.storage_path, ":h")
    if dir and dir ~= "" then
        vim.fn.mkdir(dir, "p")
    end
end

local function save_state()
    ensure_storage_dir()
    local encoded = vim.json.encode(state.data)
    local ok, err = pcall(vim.fn.writefile, { encoded }, state.config.storage_path)
    if not ok then
        vim.notify(string.format("Filemarks: failed to save - %s", err), vim.log.levels.ERROR)
    end
end

local FILE_READ_MODE = 420 -- octal 0644
local function load_state()
    if state.loaded then
        return
    end
    state.loaded = true
    local path = state.config.storage_path
    local fd = uv.fs_open(path, "r", FILE_READ_MODE)
    if not fd then
        return
    end
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
    local needs_save = false
    for project, marks in pairs(state.data) do
        if type(marks) == "table" then
            if canonicalize_project_marks(project, marks) then
                needs_save = true
            end
            for key in pairs(marks) do
                ensure_keymap(key)
            end
        end
    end
    if needs_save then
        save_state()
    end
end

local function prompt_key(prompt)
    local key = vim.fn.input(prompt or "Mark key: ")
    return key ~= "" and key or nil
end

local function reset_keymaps()
    for _, lhs in pairs(state.keymaps) do
        pcall(vim.keymap.del, "n", lhs)
    end
    for _, lhs in ipairs(state.action_keymaps) do
        pcall(vim.keymap.del, "n", lhs)
    end
    state.keymaps = {}
    state.action_keymaps = {}
end

local ACTION_MAPPINGS = {
    { "a", "add",     "Add filemark" },
    { "d", "add_dir", "Add directory mark" },
    { "r", "remove",  "Remove filemark" },
    { "l", "list",    "Edit filemarks" },
}

local function install_action_keymaps()
    local prefix = state.config.action_prefix
    if not prefix or prefix == "" then
        return
    end
    for _, action in ipairs(ACTION_MAPPINGS) do
        local key, method, desc = action[1], action[2], action[3]
        local lhs = prefix .. key
        vim.keymap.set("n", lhs, function()
            M[method]()
        end, { desc = "Filemarks: " .. desc })
        table.insert(state.action_keymaps, lhs)
    end
end

local function install_commands()
    if state.commands_installed then
        return
    end
    state.commands_installed = true

    vim.api.nvim_create_user_command("FilemarksAdd", function(opts)
        M.add(opts.fargs[1], opts.fargs[2])
    end, {
        desc = "Add/update a persistent filemark",
        nargs = "*",
        complete = "file",
    })

    vim.api.nvim_create_user_command("FilemarksAddDir", function(opts)
        M.add_dir(opts.fargs[1], opts.fargs[2])
    end, {
        desc = "Add/update a persistent directory mark (detects netrw directory)",
        nargs = "*",
        complete = "dir",
    })

    vim.api.nvim_create_user_command("FilemarksRemove", function(opts)
        M.remove(opts.fargs[1])
    end, {
        desc = "Remove a filemark from the current project",
        nargs = "?",
    })

    vim.api.nvim_create_user_command("FilemarksList", M.list, {
        desc = "Edit filemarks for the current project",
    })

    vim.api.nvim_create_user_command("FilemarksOpen", function(opts)
        local key = opts.fargs[1]
        if not key then
            vim.notify("Filemarks: provide a key to open", vim.log.levels.WARN)
            return
        end
        M.open(key)
    end, {
        desc = "Jump to the file/directory referenced by a key",
        nargs = 1,
    })
end

local function install_filetype_support()
    if state.filetype_autocmd then
        return
    end
    local group = vim.api.nvim_create_augroup("FilemarksFiletype", { clear = true })
    state.filetype_autocmd = group
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "filemarks",
        callback = function(ev)
            vim.api.nvim_set_option_value("commentstring", "# %s", { buf = ev.buf })
            highlight_comments(ev.buf)
            attach_comment_highlighter(ev.buf)
        end,
    })
end

local function generate_editor_lines(project, marks)
    local header = {
        string.format("# Filemarks for %s", project),
        "# Format: <key><space><path>. Lines starting with # are comments.",
        "# Directories are shown with a trailing /",
        "Delete/Comment a line to remove it. Save to persist changes.",
        "",
    }

    local keys = vim.tbl_keys(marks or {})
    table.sort(keys)

    local mark_lines = vim.tbl_map(function(key)
        local stored_path = marks[key]
        local display_path = relativize_path(stored_path, project)
        local resolved = resolve_project_path(stored_path, project)
        -- Add trailing / for directories
        if resolved and is_directory(resolved) and not vim.endswith(display_path, "/") then
            display_path = display_path .. "/"
        end
        return string.format("%s %s", key, display_path)
    end, keys)

    vim.list_extend(header, mark_lines)
    return header
end

local function parse_editor_buffer(buf, project)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local parsed = {}
    for idx, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "#") then
            local key, path = trimmed:match("^(%S+)%s+(.+)$")
            if not key or not path then
                return nil, string.format("Line %d is invalid. Expected '<key> <path>'", idx)
            end
            if parsed[key] then
                return nil, string.format("Duplicate key '%s' detected on line %d", key, idx)
            end
            local resolved = resolve_project_path(path, project)
            if not resolved then
                return nil, string.format("Could not resolve path on line %d", idx)
            end
            parsed[key] = relativize_path(resolved, project)
        end
    end
    return parsed
end

local function open_marks_editor(project, marks)
    local target_name = string.format("Filemarks://%s", project)

    -- Find existing buffer inline
    local existing = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == target_name then
            existing = buf
            break
        end
    end

    if existing then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == existing then
                vim.api.nvim_set_current_win(win)
                return
            end
        end
        vim.api.nvim_win_set_buf(0, existing)
        return
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "filemarks", { buf = buf })
    vim.api.nvim_buf_set_name(buf, target_name)
    vim.api.nvim_buf_set_var(buf, "filemarks_project", project)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, generate_editor_lines(project, marks))
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    highlight_comments(buf)

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf,
        callback = function()
            local ok, project_var = pcall(vim.api.nvim_buf_get_var, buf, "filemarks_project")
            if not ok then
                vim.notify("Filemarks: unable to determine project for editor buffer", vim.log.levels.ERROR)
                return
            end
            local parsed, parse_err = parse_editor_buffer(buf, project_var)
            if not parsed then
                vim.notify(string.format("Filemarks: %s", parse_err), vim.log.levels.ERROR)
                return
            end
            if next(parsed) then
                state.data[project_var] = parsed
            else
                state.data[project_var] = nil
            end
            save_state()
            rebuild_jump_keymaps()
            vim.api.nvim_set_option_value("modified", false, { buf = buf })
            vim.notify("Filemarks: saved changes", vim.log.levels.INFO)
        end,
    })
end

function M.configure(opts)
    reset_keymaps()
    state.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
    state.loaded = false
    state.data = {}
    load_state()
    install_action_keymaps()
end

function M.add(key, file_path)
    load_state()
    key = key or prompt_key("Add mark key: ")
    if not key then
        return
    end
    local resolved_file = normalize_path(file_path or vim.api.nvim_buf_get_name(0))
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
    local display_path = relativize_path(resolved_file, project)
    local existing_value = marks[key]

    if existing_value and type(existing_value) == "string" and existing_value ~= "" then
        local resolved_existing = resolve_project_path(existing_value, project)
        if resolved_existing == resolved_file then
            vim.notify(string.format("Filemarks: %s already points to %s", key, display_path), vim.log.levels.INFO)
            return
        end
    end

    if existing_value then
        local current_display = relativize_path(existing_value, project)
        local new_display = relativize_path(resolved_file, project)
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
    local stored_path = relativize_path(resolved_file, project)
    marks[key] = stored_path
    save_state()
    ensure_keymap(key)
    vim.notify(string.format("Filemarks: added %s -> %s", key, display_path), vim.log.levels.INFO)
end

function M.add_dir(key, dir_path)
    load_state()
    key = key or prompt_key("Add directory mark key: ")
    if not key then
        return
    end
    -- Default to current directory if no path provided
    local target_dir = dir_path
    if not target_dir or target_dir == "" then
        -- Check if we're in a netrw buffer
        local ok, netrw_dir = pcall(vim.api.nvim_buf_get_var, 0, "netrw_curdir")
        if ok and netrw_dir and netrw_dir ~= "" then
            target_dir = netrw_dir
        else
            -- Check if current buffer is a directory
            local current_file = vim.api.nvim_buf_get_name(0)
            if current_file and current_file ~= "" then
                if is_directory(current_file) then
                    target_dir = current_file
                else
                    target_dir = vim.fn.fnamemodify(current_file, ":p:h")
                end
            else
                target_dir = vim.fn.getcwd()
            end
        end
    end

    local resolved_dir = normalize_path(target_dir)
    if not resolved_dir or resolved_dir == "" then
        vim.notify("Filemarks: unable to determine directory path", vim.log.levels.WARN)
        return
    end

    if not is_directory(resolved_dir) then
        vim.notify(string.format("Filemarks: '%s' is not a directory", target_dir), vim.log.levels.WARN)
        return
    end

    M.add(key, resolved_dir)
end

function M.remove(key)
    load_state()
    key = key or prompt_key("Remove mark key: ")
    if not key then
        return
    end
    local marks, project_or_err = get_marks()
    if not marks then
        vim.notify(string.format("Filemarks: %s", project_or_err or "unknown error"), vim.log.levels.ERROR)
        return
    end
    local project = project_or_err
    if not marks[key] then
        vim.notify(string.format("Filemarks: %s not defined for this project", key), vim.log.levels.WARN)
        return
    end
    marks[key] = nil
    if vim.tbl_isempty(marks) then
        state.data[project] = nil
    end
    save_state()
    if not key_in_use(key) then
        clear_keymap(key)
    end
    vim.notify(string.format("Filemarks: removed %s", key), vim.log.levels.INFO)
end

function M.list()
    load_state()
    local marks, project_or_err = get_marks()
    if not marks then
        vim.notify(string.format("Filemarks: %s", project_or_err or "unknown error"), vim.log.levels.ERROR)
        return
    end
    local project = project_or_err
    open_marks_editor(project, marks)
end

function M.open(key)
    load_state()
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
        vim.notify(string.format("Filemarks: %s not set for this project", key), vim.log.levels.WARN)
        return
    end
    local path = marks[key]
    if not path or path == "" then
        vim.notify(string.format("Filemarks: invalid path for %s", key), vim.log.levels.ERROR)
        return
    end
    local resolved = resolve_project_path(path, project)
    if not resolved then
        vim.notify(string.format("Filemarks: unable to resolve %s for project", key), vim.log.levels.ERROR)
        return
    end

    if is_directory(resolved) then
        -- For directories, use Explore to open in netrw
        vim.cmd({ cmd = "Explore", args = { resolved } })
        return
    end

    if focus_buffer_for_path(resolved) then
        return
    end
    local cwd = normalize_path(vim.fn.getcwd())
    local edit_arg = resolved
    if cwd == project and type(path) == "string" and path ~= "" and not is_absolute_path(path) then
        edit_arg = path
    end
    vim.cmd({ cmd = "edit", args = { edit_arg } })
end

function M.setup(opts)
    M.configure(opts or {})
    install_commands()
    install_filetype_support()
end

return M
