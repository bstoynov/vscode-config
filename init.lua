-- sync system clipboard
vim.opt.clipboard = 'unnamedplus'

-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = false }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Case-insensitive searching 
vim.opt.ignorecase = true
-- UNLESS \C or one or more capital letters in the search term
vim.opt.smartcase = true

-- Increase memory to fix crashes inside VSCode
-- vim.opt.maxmempattern = 2000

-- No Highlight when seraching
vim.o.hlsearch = false

-- Disable Cmd + D in insert mode to allow for multiple cursors in vscode
vim.api.nvim_set_keymap('i', '<D-d>', '', { noremap = true, silent = true })

-- Remap W to w because when saving I don't let out shift quick enough
vim.api.nvim_create_user_command("W", "w", {})
