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
local scope_module = require("quickfix_review.scope")
local review_scope = scope_module.resolve("repository")
assert(persist.write({
	namespace = "quickfix_review",
	name = "review",
	scope = review_scope,
	snapshot = {
		version = 1,
		kind = "quickfix",
		title = "Quickfix Review",
		context = { quickfix_review = { version = 1, role = "notes", scope_id = scope_module.id(review_scope) } },
		items = {},
	},
}))
local save, watch = persist.save, persist.watch
local saves, watches = 0, 0
persist.save = function(opts)
	saves = saves + 1
	return save(opts)
end
persist.watch = function(opts)
	watches = watches + 1
	return watch(opts)
end
notes.setup({
	persist_review_list = true,
	scope_policy = "repository",
	agent = { response = { watch = false } },
})
-- setup restores the persisted review list on the next event-loop tick.
assert(vim.wait(1000, function()
	return watches == 1
end))
assert(saves == 0 and watches == 1)
persist.save, persist.watch = save, watch
assert(persist.delete({ namespace = "quickfix_review", name = "review", scope = review_scope }))

local file = vim.fs.joinpath(root, "README.md")
vim.fn.setqflist({}, "r", { title = "persisted", items = { { filename = file, lnum = 1, text = "saved" } } })
local target = { kind = "quickfix", id = vim.fn.getqflist({ id = 0 }).id }
local scope = notes.scope()
assert(scope)
assert(notes.save_list("integration", { list = target, watch = false }))
	assert(persist.load({ namespace = "quickfix_review", name = "integration", scope = scope }))
	assert(persist.delete({ namespace = "quickfix_review", name = "integration", scope = scope }))

print("quickfix_review with persist tests passed")
