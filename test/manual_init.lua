local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
local projects = vim.fn.fnamemodify(root, ":h")

for env, name in pairs({
	QUICKFIX_PERSIST_PATH = "quickfix-persist.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
}) do
	local path = vim.env[env]
	vim.opt.rtp:prepend(path and path ~= "" and path or vim.fs.joinpath(projects, name))
end
vim.opt.rtp:prepend(root)

vim.cmd("cd " .. vim.fn.fnameescape(root))
vim.g.mapleader = " "

require("quickfix_persist").setup()
require("quickfix_review").setup()
