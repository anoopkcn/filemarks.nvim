local state = require("filemarks.state")
local marks = require("filemarks.marks")

local M = {}

function M.install()
    if state.commands_installed then
        return
    end
    state.commands_installed = true

    vim.api.nvim_create_user_command("FilemarksAdd", function(opts)
        marks.add(opts.fargs[1], opts.fargs[2])
    end, {
        desc = "Add/update a persistent filemark",
        nargs = "*",
        complete = "file",
    })

    vim.api.nvim_create_user_command("FilemarksAddDir", function(opts)
        marks.add_dir(opts.fargs[1], opts.fargs[2])
    end, {
        desc = "Add/update a persistent directory mark (detects netrw directory)",
        nargs = "*",
        complete = "dir",
    })

    vim.api.nvim_create_user_command("FilemarksRemove", function(opts)
        marks.remove(opts.fargs[1])
    end, {
        desc = "Remove a filemark from the current project",
        nargs = "?",
    })

    vim.api.nvim_create_user_command("FilemarksList", function(opts)
        marks.list(opts)
    end, {
        desc = "Edit filemarks for the current project",
    })

    vim.api.nvim_create_user_command("FilemarksOpen", function(opts)
        local key = opts.fargs[1]
        if not key then
            vim.notify("Filemarks: provide a key to open", vim.log.levels.WARN)
            return
        end
        marks.open(key)
    end, {
        desc = "Jump to the file/directory referenced by a key",
        nargs = 1,
    })
end

return M
