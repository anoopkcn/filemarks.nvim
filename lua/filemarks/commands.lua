local state = require("filemarks.state")

local M = {}

-- Commands lazy-require filemarks.marks so this module can be loaded from
-- plugin/filemarks.lua without pulling in the rest of the plugin
function M.install()
    if state.commands_installed then
        return
    end
    state.commands_installed = true

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
end

return M
