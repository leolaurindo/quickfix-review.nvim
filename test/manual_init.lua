local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
local projects = vim.fn.fnamemodify(root, ":h")

for _, name in ipairs({
	"quickfix-persist.nvim",
	"quickfix-export.nvim",
	"quickfix-actions.nvim",
	"reviewnotes.nvim",
}) do
	vim.opt.rtp:prepend(vim.fs.joinpath(projects, name))
end

vim.cmd("cd " .. vim.fn.fnameescape(root))
vim.g.mapleader = " "

require("quickfix_persist").setup()
require("quickfix_notes").setup()
