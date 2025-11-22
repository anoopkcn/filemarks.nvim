# filemarks.nvim

A Neovim plugin for managing persistent, project-scoped file and directory bookmarks.

## Features

- **Project-aware**: Automatically detects project boundaries and scopes marks per project
- **Persistent**: Marks survive across Neovim sessions
- **File and directory support**: Bookmark both files and directories
- **Automatic keybindings**: Creates jump keybindings dynamically as you add marks
- **Buffer-based editor**: Edit all marks for a project in a dedicated buffer
- **Relative paths**: Stores paths relative to project root for portability

**Comparison with Vim's built-in marks**

| Feature | Vim marks | filemarks.nvim |
|---------|-----------|----------------|
| Persist across sessions | Limited (uppercase marks only) | Yes (all marks) |
| Project-scoped | No | Yes |
| Directory support | No | Yes |
| Custom keybindings | No | Yes |
| Buffer-based editor | No | Yes |
| Relative paths | No | Yes |


## Installation

### Using neovim native [vim.pack](https://neovim.io/doc/user/pack.html#vim.pack)
```lua
vim.pack.add({ src = "https://github.com/anoopkcn/filemarks.nvim" })
require('filemarks').setup()
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'anoopkcn/filemarks.nvim',
  config = function()
    require('filemarks').setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'anoopkcn/filemarks.nvim',
  config = function()
    require('filemarks').setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'anoopkcn/filemarks.nvim'

lua << EOF
require('filemarks').setup()
EOF
```

## Quick Start

After installation, the plugin provides default keybindings (assuming `<leader>` is space):

**Action keybindings:**
- `<leader>Ma` - Add filemark for current file
- `<leader>Md` - Add directory mark
- `<leader>Mr` - Remove filemark
- `<leader>Ml` - List/edit filemarks for current project

**Jump keybindings** (created automatically):
- `<leader>m{key}` - Jump to mark `{key}`

### Example workflow

```vim
" 1. Open your main project file
:edit src/main.lua

" 2. Mark it with key 'm'
:FilemarksAdd m
" or press <leader>Ma and enter 'm'

" 3. Later, from anywhere in the project, jump back
<leader>mm
" Opens src/main.lua instantly
```

## Configuration

Default configuration:

```lua
require('filemarks').setup({
  goto_prefix = "<leader>m",      -- Prefix for jump keybindings
  action_prefix = "<leader>M",    -- Prefix for action keybindings
  storage_path = vim.fn.stdpath("state") .. "/filemarks.json",
  project_markers = { ".git", ".hg", ".svn" },  -- Files/dirs that mark project root
  -- Command (string) or function used to open the list buffer in a window.
  -- Examples:
  --   "rightbelow vsplit"
  --   function() vim.cmd("topleft split") end
  list_open_cmd = nil,
})
```

### Custom keybinding prefixes

```lua
require('filemarks').setup({
  goto_prefix = "'",              -- Use ' like Vim's built-in marks
  action_prefix = "<leader>b",    -- Custom action prefix
})
```

### Disable keybindings

Set a prefix to empty string to disable that category of keybindings:

```lua
require('filemarks').setup({
  goto_prefix = "",      -- Disable jump keybindings
  action_prefix = "",    -- Disable action keybindings
})
```

### Custom project markers

```lua
require('filemarks').setup({
  project_markers = { ".git", "package.json", "Cargo.toml", "pyproject.toml" },
})

### Choose where the list opens

```lua
require('filemarks').setup({
  -- Open the list in a rightbelow vertical split by default
  list_open_cmd = "rightbelow vsplit",
})
```
```

## Commands

### `:FilemarksAdd [key] [file_path]`

Add or update a filemark.

```vim
:FilemarksAdd                    " Prompt for key, mark current file
:FilemarksAdd m                  " Mark current file as 'm'
:FilemarksAdd c src/config.lua   " Mark config.lua as 'c'
```

### `:FilemarksAddDir [key] [dir_path]`

Add or update a directory mark.

```vim
:FilemarksAddDir                 " Prompt for key, mark current directory context
:FilemarksAddDir d               " Mark current directory as 'd'
:FilemarksAddDir t tests/        " Mark tests/ directory as 't'
```

When called without a directory path:
1. Uses netrw directory if in a netrw buffer
2. Falls back to current file's directory
3. Falls back to current working directory

### `:FilemarksRemove [key]`

Remove a filemark from the current project.

```vim
:FilemarksRemove                 " Prompt for key
:FilemarksRemove m               " Remove mark 'm'
```

### `:FilemarksList`

Open an editor buffer to view and edit all marks for the current project.

```vim
:FilemarksList
:rightbelow vertical FilemarksList   " Use command modifiers to choose the split/tab
```

The editor buffer format:

```
# Filemarks for /path/to/project
# Format: <key><space><path>. Lines starting with # are comments.
# Directories are shown with a trailing /
# Delete/Comment a line to remove it. Save to persist changes.

c src/config.lua
d tests/
m main.go
```

Edit the buffer and save (`:w`) to persist changes. Keybindings are automatically updated.

### `:FilemarksOpen {key}`

Jump to a mark (typically accessed via jump keybindings instead).

```vim
:FilemarksOpen m                 " Jump to mark 'm'
```

## Use Cases

### Navigate large codebases

```vim
" Mark key files in your project
m -> src/main.rs           (main entry point)
c -> config/settings.toml  (configuration)
r -> src/routes.rs         (routing)
t -> tests/                (test directory)
```

### Per-project shortcuts

Marks are project-specific, so you can use the same keys across different projects:

```
Project A:
  m -> app/main.js
  c -> config/app.json

Project B:
  m -> cmd/main.go
  c -> config.yaml
```

### Directory bookmarks

```vim
" In a directory you frequently visit
:FilemarksAddDir d

" Jump back anytime
<leader>md
" Opens directory in netrw
```

## Lua API

### `require('filemarks').setup(opts)`

Initialize the plugin with configuration options.

```lua
require('filemarks').setup({
  goto_prefix = "<leader>m",
})
```

### `require('filemarks').add(key, file_path)`

Programmatically add a filemark.

```lua
local filemarks = require('filemarks')

-- Mark current file
filemarks.add('m')

-- Mark specific file
filemarks.add('c', 'src/config.lua')
```

### `require('filemarks').add_dir(key, dir_path)`

Programmatically add a directory mark.

```lua
filemarks.add_dir('d', 'tests/')
```

### `require('filemarks').remove(key)`

Remove a filemark.

```lua
filemarks.remove('m')
```

### `require('filemarks').list()`

Open the marks editor.

```lua
filemarks.list()
```

### `require('filemarks').open(key)`

Jump to a mark.

```lua
filemarks.open('m')
```

## Storage

Filemarks are stored in a JSON file at the configured `storage_path` (default: `~/.local/state/nvim/filemarks.json`).

The storage format:

```json
{
  "/absolute/path/to/project1": {
    "m": "src/main.lua",
    "c": "config/init.lua",
    "d": "tests/"
  },
  "/absolute/path/to/project2": {
    "m": "main.go",
    "t": "main_test.go"
  }
}
```

### Syncing across machines

To sync marks across machines:

1. Set `storage_path` to a synced directory:
```lua
require('filemarks').setup({
  storage_path = "~/Dropbox/.config/nvim/filemarks.json",
})
```

2. Ensure project paths are consistent across machines, or use relative paths within projects.

## License

MIT

## Author

[@anoopkcn](https://github.com/anoopkcn)
