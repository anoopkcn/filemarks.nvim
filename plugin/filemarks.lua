if vim.g.loaded_filemarks then
    return
end
vim.g.loaded_filemarks = 1

local keymaps = require("filemarks.keymaps")
require("filemarks.config")

vim.api.nvim_create_user_command("FilemarksAdd", function(opts)
    require("filemarks.marks").add(opts.fargs[1], opts.fargs[2])
end, {
    desc = "Add/update a persistent filemark",
    nargs = "*",
    complete = "file",
})

vim.api.nvim_create_user_command("FilemarksAddDir", function(opts)
    require("filemarks.marks").add_dir(opts.fargs[1], opts.fargs[2])
end, {
    desc = "Add/update a persistent directory mark (detects netrw directory)",
    nargs = "*",
    complete = "dir",
})

vim.api.nvim_create_user_command("FilemarksRemove", function(opts)
    require("filemarks.marks").remove(opts.fargs[1])
end, {
    desc = "Remove a filemark from the current project",
    nargs = "?",
})

vim.api.nvim_create_user_command("FilemarksList", function(opts)
    require("filemarks.marks").list(opts)
end, {
    desc = "Edit filemarks for the current project",
})

vim.api.nvim_create_user_command("FilemarksToggle", function(opts)
    require("filemarks.marks").toggle(opts)
end, {
    desc = "Toggle the filemarks list window",
})

vim.api.nvim_create_user_command("FilemarksOpen", function(opts)
    local key = opts.fargs[1]
    if not key then
        vim.notify("Filemarks: provide a key to open", vim.log.levels.WARN)
        return
    end
    require("filemarks.marks").open(key)
end, {
    desc = "Jump to the file/directory referenced by a key",
    nargs = 1,
})

require("filemarks.state").commands_installed = true

keymaps.install_action_keymaps({
    { key = "a", desc = "Add filemark",         fn = function() require("filemarks.marks").add() end },
    { key = "d", desc = "Add directory mark",   fn = function() require("filemarks.marks").add_dir() end },
    { key = "r", desc = "Remove filemark",      fn = function() require("filemarks.marks").remove() end },
    { key = "l", desc = "Edit filemarks",       fn = function() require("filemarks.marks").list() end },
    { key = "t", desc = "Toggle filemarks list", fn = function() require("filemarks.marks").toggle() end },
})

keymaps.install_goto_prefix_fallback()
