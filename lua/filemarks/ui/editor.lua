-- The list editor's external interface: open and close the filemarks
-- list for a project. Composes two internal modules: ui/placement.lua
-- (windows) and ui/document.lua (the buffer and its render/parse).

local document = require("filemarks.ui.document")
local placement = require("filemarks.ui.placement")

local M = {}

function M.open_editor(project, marks, cmd_opts)
    document.install_filetype_support()
    local target_name = document.buffer_name(project)
    local function is_this_project(buf)
        return vim.api.nvim_buf_get_name(buf) == target_name
    end

    local existing_win, existing = placement.find_window(is_this_project)
    if existing_win then
        vim.api.nvim_set_current_win(existing_win)
        if not document.has_unsaved_changes(existing) then
            document.refresh(existing, project, marks)
        end
        document.ensure_comment_match(existing_win)
        return
    end

    local mods = cmd_opts and cmd_opts.mods or ""
    local target_win = placement.acquire(mods)

    existing = document.find_buffer(target_name)
    if existing then
        vim.api.nvim_win_set_buf(target_win, existing)
        if not document.has_unsaved_changes(existing) then
            document.refresh(existing, project, marks)
        end
        document.configure_comment(existing, target_win)
        return
    end

    document.create(target_win, project, marks)
end

function M.close_editor()
    -- Prefer the current window so closing from inside a list targets that
    -- list, not another project's
    local cur_win = vim.api.nvim_get_current_win()
    local cur_buf = vim.api.nvim_win_get_buf(cur_win)
    if document.is_list_buffer(cur_buf) then
        return placement.close(cur_win, cur_buf)
    end
    local win, buf = placement.find_window(document.is_list_buffer)
    if not win then
        return false
    end
    return placement.close(win, buf)
end

M.install_filetype_support = document.install_filetype_support

return M
