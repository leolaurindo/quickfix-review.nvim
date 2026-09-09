vim.env.XDG_DATA_HOME = "/tmp/quickfix_review-persist-test-data"
vim.env.XDG_STATE_HOME = "/tmp/quickfix_review-persist-test-state"
local root = vim.fn.getcwd()

local function add_dependency(env, sibling)
	local path = vim.env[env]
		or vim.fs.joinpath(vim.fn.fnamemodify(root, ":h"), sibling)
	vim.opt.rtp:prepend(path)
end

add_dependency("QUICKFIX_ACTIONS_PATH", "quickfix-actions.nvim")
add_dependency("QUICKFIX_EXPORT_PATH", "quickfix-export.nvim")
add_dependency("QUICKFIX_PERSIST_PATH", "quickfix-persist.nvim")
vim.opt.rtp:prepend(root)

local notes = require("quickfix_review")
local persist = require("quickfix_persist")
notes.setup({ persist_review_list = false })

local file = vim.fs.joinpath(root, "README.md")
vim.fn.setqflist({}, "r", { title = "persisted", items = { { filename = file, lnum = 1, text = "saved" } } })
local target = { kind = "quickfix", id = vim.fn.getqflist({ id = 0 }).id }
local scope = notes.scope()
assert(scope)
assert(notes.save_list("integration", { list = target, watch = false }))
	assert(persist.load({ namespace = "quickfix_review", name = "integration", scope = scope }))
	assert(persist.delete({ namespace = "quickfix_review", name = "integration", scope = scope }))

print("quickfix_review with persist tests passed")
