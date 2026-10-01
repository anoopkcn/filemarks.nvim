# rename the buffer key to buf (soft-deprecated in Nvim 0.13)

- STATUS: OPEN
- PRIORITY: 100
- TAGS:

`lua/filemarks/ui/document.lua:189`, `:202` (`nvim_create_autocmd`) and `:246`, `:255`
(`vim.keymap.set`).

Nvim 0.13 renamed the `buffer` key to `buf`. `buffer` is still accepted;
`runtime/lua/vim/keymap.lua` notes "soft-deprecate `buffer` in 0.13, remove in 0.15".

Trade-off: `buf` in the autocmd API exists only from 0.13, so switching drops 0.12
support. Decide the minimum supported Nvim version first.

Found in the Neovim 0.13 review on 2026-10-01.
