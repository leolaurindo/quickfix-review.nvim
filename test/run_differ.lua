local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	vim.opt.rtp:prepend(vim.env[env] or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)

local root = vim.fn.getcwd()
local map = {
	lines = {
		[1] = { new = 1, old = 1, kind = "context" },
		[4] = { new = 2, old = 2, kind = "context" },
		[7] = { new = 4, old = 4, kind = "context" },
	},
}
local view = {
	model = { root = root, path = "README.md" },
	map_for = function(_, kind)
		return kind == "unified" and map or nil
	end,
}
package.preload["differ.view"] = function()
	return { for_buf = function() return view end }
end

local review = require("quickfix_review")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local marks = require("quickfix_review.marks")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })

local owned, target = lists.ensure_owned({ title = "Quickfix Review" }, require("quickfix_review.scope").id(review.scope()))
local item = { filename = vim.fs.joinpath(root, "README.md"), lnum = 2, valid = 1, text = "mapped range", user_data = {} }
assert(annotations.set(item, { root = root, path = "README.md", line = 2, line_end = 4, resolver = "normal" }, "mapped range"))
owned.items[#owned.items + 1] = item
assert(lists.replace(target, owned.items, 1, owned.changedtick))

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "differ://README.md")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three", "four", "five", "six", "seven" })
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
marks.render(buf)

local ns = vim.api.nvim_get_namespaces().quickfix_review
local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
assert(#extmarks == 2)
assert(extmarks[1][2] == 3 and extmarks[2][2] == 6)
print("quickfix_review Differ marks tests passed")
