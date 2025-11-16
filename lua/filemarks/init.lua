local M = {}

local uv = vim.uv or vim.loop

local default_config = {
    goto_prefix = "<leader>m",
    action_prefix = "<leader>s",
    storage_path = vim.fn.stdpath("state") .. "/filemarks.json",
    project_markers = { ".git", ".hg", ".svn" },
}

local state = {
    config = vim.deepcopy(default_config),
    data = {},
    keymaps = {},
    action_keymaps = {},
    loaded = false,
}

local function normalize_path(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local ok, resolved = pcall(uv.fs_realpath, path)
    if ok and resolved then
        return vim.fs.normalize(resolved)
    end
    return vim.fs.normalize(path)
end

local function detect_project(path)
    local target = path and vim.fn.fnamemodify(path, ":p:h") or nil
    local ok, root = pcall(vim.fs.root, target or 0, state.config.project_markers)
    if ok and root then
        return normalize_path(root)
    end
    return normalize_path(vim.fn.getcwd())
end

local function get_marks(path_hint)
    local project = detect_project(path_hint)
    if not project then
        return nil, "Unable to determine project directory"
    end
    state.data[project] = state.data[project] or {}
    return state.data[project], project
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
    if not lhs then
        return
    end
    pcall(vim.keymap.del, "n", lhs)
    state.keymaps[key] = nil
end

local function ensure_keymap(key)
    if state.keymaps[key] then
        return
    end
    if not state.config.goto_prefix or state.config.goto_prefix == "" then
        return
    end
    local lhs = state.config.goto_prefix .. key
    vim.keymap.set("n", lhs, function()
        M.open(key)
    end, { desc = string.format("Filemarks: jump to %s", key) })
    state.keymaps[key] = lhs
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

local function load_state()
    if state.loaded then
        return
    end
    state.loaded = true
    local path = state.config.storage_path
    local fd = uv.fs_open(path, "r", 420)
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
    for _, marks in pairs(state.data) do
        for key in pairs(marks) do
            ensure_keymap(key)
        end
    end
end

local function prompt_key(prompt)
    local key = vim.fn.input(prompt or "Mark key: ")
    if key == "" then
        return nil
    end
    return key
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

local function install_action_keymaps()
    local prefix = state.config.action_prefix
    if not prefix or prefix == "" then
        return
    end
    local actions = {
        { "a", function()
            M.add()
        end, "Add filemark" },
        { "r", function()
            M.remove()
        end, "Remove filemark" },
        { "l", M.list, "List filemarks" },
    }
    for _, action in ipairs(actions) do
        local lhs = prefix .. action[1]
        vim.keymap.set("n", lhs, action[2], { desc = "Filemarks: " .. action[3] })
        table.insert(state.action_keymaps, lhs)
    end
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
    if marks[key] == resolved_file then
        vim.notify(string.format("Filemarks: %s already points to %s", key, resolved_file), vim.log.levels.INFO)
        return
    end
    marks[key] = resolved_file
    save_state()
    ensure_keymap(key)
    vim.notify(string.format("Filemarks: added %s -> %s", key, resolved_file), vim.log.levels.INFO)
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
    if vim.tbl_isempty(marks) then
        vim.notify("Filemarks: no marks for this project", vim.log.levels.INFO)
        return
    end
    local project = project_or_err
    local lines = { string.format("Filemarks for %s:", project) }
    local keys = vim.tbl_keys(marks)
    table.sort(keys)
    for _, key in ipairs(keys) do
        local path = marks[key]
        table.insert(lines, string.format("  %s -> %s", key, path))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.open(key)
    load_state()
    if not key or key == "" then
        return
    end
    local marks, err = get_marks()
    if not marks then
        vim.notify(string.format("Filemarks: %s", err or "unknown error"), vim.log.levels.ERROR)
        return
    end
    if not marks[key] then
        vim.notify(string.format("Filemarks: %s not set for this project", key), vim.log.levels.WARN)
        return
    end
    local path = marks[key]
    if not path or path == "" then
        vim.notify(string.format("Filemarks: invalid path for %s", key), vim.log.levels.ERROR)
        return
    end
    vim.cmd({ cmd = "edit", args = { path } })
end

function M.setup(opts)
    M.configure(opts or {})
end

return M
