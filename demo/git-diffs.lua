local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":p:h:h")
local projects = vim.fn.fnamemodify(plugin_root, ":h")
local root = "/tmp/quickfix-review-diffs-demo"
vim.fn.delete(root, "rf")
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "one", "two", "three", "four" }, root .. "/example.txt")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
assert(vim.system({ "git", "-C", root, "add", "." }):wait().code == 0)
assert(vim.system({ "git", "-C", root, "-c", "user.name=Demo", "-c", "user.email=demo@example.com", "commit", "-qm", "base" }):wait().code == 0)
vim.fn.writefile({ "one", "TWO", "THREE", "four" }, root .. "/example.txt")
for env, sibling in pairs({ QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim", QUICKFIX_EXPORT_PATH = "quickfix-export.nvim", QUICKFIX_DIFFS_PATH = "quickfix-diffs.nvim" }) do
	vim.opt.rtp:prepend(vim.env[env] or (projects .. "/" .. sibling))
end
vim.opt.rtp:prepend(plugin_root)
vim.cmd.cd(vim.fn.fnameescape(root))
require("quickfix_review").setup({ nerd_font = false, persist_review_list = false, scope_policy = "repository" })
require("quickfix_diffs").setup({ open = true })
