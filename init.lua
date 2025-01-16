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
