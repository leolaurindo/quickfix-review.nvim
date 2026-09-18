local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	vim.opt.rtp:prepend(vim.env[env] or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)

local root = vim.fn.getcwd()
local new_map = {
	lines = {
		[1] = { old = 1, new = 1, kind = "context" },
		[4] = { new = 2, kind = "new" },
		[7] = { new = 4, kind = "new" },
	},
	from_new = { [1] = 1, [2] = 4, [4] = 7 },
	from_old = { [1] = 1 },
}
local old_map = {
	lines = {
		[1] = { old = 1, new = 1, kind = "context" },
		[3] = { old = 2, kind = "old" },
		[6] = { old = 4, kind = "old" },
	},
	from_new = { [1] = 1 },
	from_old = { [1] = 1, [2] = 3, [4] = 6 },
}
local unified_map = {
	lines = {
		[1] = { old = 1, new = 1, kind = "context" },
		[4] = { old = 2, kind = "old" },
		[7] = { new = 2, kind = "new" },
	},
	from_new = { [1] = 1, [2] = 7 },
	from_old = { [1] = 1, [2] = 4 },
}
local view = { model = { root = root, path = "README.md" }, columns = {} }
package.preload["differ.view"] = function()
	return { for_buf = function() return view end }
end

local review = require("quickfix_review")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local marks = require("quickfix_review.marks")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })

local owned, target = lists.ensure_owned({ title = "Quickfix Review" }, require("quickfix_review.scope").id(review.scope()))
for _, note in ipairs({
	{ location = { root = root, path = "README.md", line = 2, line_end = 4, resolver = "normal" }, text = "new range" },
	{ location = { root = root, path = "README.md", line = 2, line_end = 4, side = "old", resolver = "normal" }, text = "old range" },
	{ location = { root = root, path = "README.md", line = 2, side = "old", revision = "historical", resolver = "normal" }, text = "historical old" },
}) do
	local item = { filename = vim.fs.joinpath(root, "README.md"), lnum = 2, valid = 1, text = note.text, user_data = {} }
	assert(annotations.set(item, note.location, note.text))
	owned.items[#owned.items + 1] = item
end
assert(lists.replace(target, owned.items, 1, owned.changedtick))

local new_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(new_buf, "differ://new/README.md")
vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, { "one", "two", "three", "four", "five", "six", "seven" })
local old_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(old_buf, "differ://old/README.md")
vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, { "one", "two", "three", "four", "five", "six", "seven" })
local unified_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(unified_buf, "differ://README.md")
vim.api.nvim_buf_set_lines(unified_buf, 0, -1, false, { "one", "two", "three", "four", "five", "six", "seven" })
view.columns = {
	{ bufnr = old_buf, side = "old", map = old_map },
	{ bufnr = new_buf, side = "new", map = new_map },
	{ bufnr = unified_buf, side = "unified", map = unified_map },
}

local ns = vim.api.nvim_get_namespaces().quickfix_review
vim.api.nvim_set_current_buf(new_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
marks.render(new_buf)
local new_marks = vim.api.nvim_buf_get_extmarks(new_buf, ns, 0, -1, {})
assert(#new_marks == 2 and new_marks[1][2] == 3 and new_marks[2][2] == 6)

vim.api.nvim_set_current_buf(old_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
marks.render(old_buf)
local old_marks = vim.api.nvim_buf_get_extmarks(old_buf, ns, 0, -1, {})
assert(#old_marks == 2 and old_marks[1][2] == 2 and old_marks[2][2] == 5)

vim.api.nvim_set_current_buf(unified_buf)
vim.api.nvim_win_set_cursor(0, { 7, 0 })
marks.render(unified_buf)
local unified_marks = vim.api.nvim_buf_get_extmarks(unified_buf, ns, 0, -1, {})
assert(#unified_marks == 3 and unified_marks[1][2] == 3 and unified_marks[2][2] == 3 and unified_marks[3][2] == 6)
print("quickfix_review Differ marks tests passed")
