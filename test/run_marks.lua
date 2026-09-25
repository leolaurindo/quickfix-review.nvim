-- Marks must not be repainted when nothing about them changed: ShellCmdPost fires for
-- every shell command any plugin runs (pollers, git, tmux, ...), and re-rendering on it
-- repaints marked lines with no cursor movement and no popup involved.
local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	vim.opt.rtp:prepend(vim.env[env] or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "one", "two", "three", "four", "five" }, root .. "/file.txt")
vim.fn.system({ "git", "-C", root, "init", "-q" })
vim.cmd.cd(root)
vim.cmd.edit(root .. "/file.txt")

local review = require("quickfix_review")
local ui = require("quickfix_review.ui")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })
ui.note_input = function(_, callback)
	callback({ text = "note for the repaint test" })
end
vim.api.nvim_win_set_cursor(0, { 3, 0 })
review.add()

local namespace = vim.api.nvim_get_namespaces().quickfix_review
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 1, "note mark should be rendered")

local writes = 0
local set_extmark, clear_namespace = vim.api.nvim_buf_set_extmark, vim.api.nvim_buf_clear_namespace
vim.api.nvim_buf_set_extmark = function(buf, ns, ...)
	if ns == namespace then writes = writes + 1 end
	return set_extmark(buf, ns, ...)
end
vim.api.nvim_buf_clear_namespace = function(buf, ns, ...)
	if ns == namespace then writes = writes + 1 end
	return clear_namespace(buf, ns, ...)
end

vim.api.nvim_exec_autocmds("ShellCmdPost", {})
vim.api.nvim_exec_autocmds("ShellCmdPost", {})
vim.api.nvim_exec_autocmds("FocusGained", {})
vim.api.nvim_buf_set_extmark, vim.api.nvim_buf_clear_namespace = set_extmark, clear_namespace
assert(writes == 0, "ShellCmdPost/FocusGained without a scope change must not repaint, got " .. writes)
print("quickfix_review mark repaint tests passed")
