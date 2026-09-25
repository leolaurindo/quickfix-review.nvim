local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	vim.opt.rtp:prepend(vim.env[env] or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)

local review = require("quickfix_review")
local resolver = require("quickfix_review.resolver")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })
assert(vim.wait(1000, function()
	return review.scope() ~= nil
end))

assert(package.loaded.deltaview == nil)
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "deltaview://diff/review")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"header", "", "", "added", "", "context", "", "deleted", "", "another file",
})
vim.api.nvim_buf_set_var(buf, "git_root", project)
vim.api.nvim_buf_set_var(buf, "delta_diff_data_set", {
	{ formatted_diff_line_num = 0, type = "header", old_path = "first.lua", new_path = "first.lua" },
	{ formatted_diff_line_num = 3, type = "added", new_path = "README.md", new_line_num = 7 },
	{
		formatted_diff_line_num = 5,
		type = "context",
		old_path = "README.md",
		new_path = "README.md",
		old_line_num = 8,
		new_line_num = 9,
	},
	{ formatted_diff_line_num = 7, type = "deleted", old_path = "README.md", old_line_num = 10 },
	{ formatted_diff_line_num = 9, type = "added", new_path = "second.lua", new_line_num = 1 },
})
vim.api.nvim_set_current_buf(buf)

local function at(row)
	vim.api.nvim_win_set_cursor(0, { row, 0 })
	return resolver.location(buf)
end

assert(resolver.detect(buf).name == "deltaview")
local added = assert(at(4))
assert(added.path == "README.md" and added.line == 7 and added.side == "new")
local context = assert(at(6))
assert(context.path == "README.md" and context.line == 9 and context.side == "new")
local deleted = assert(at(8))
assert(deleted.path == "README.md" and deleted.line == 10 and deleted.side == "old")
local second_file = assert(at(10))
assert(second_file.path == "second.lua" and second_file.line == 1)
local unmappable, unmappable_err = at(1)
assert(not unmappable and unmappable_err:find("not on a mappable diff line", 1, true))

local ui = require("quickfix_review.ui")
local old_input = ui.note_input
ui.note_input = function(_, callback)
	callback({ text = "DeltaView integration note" })
end
vim.api.nvim_win_set_cursor(0, { 4, 0 })
review.add()
ui.note_input = old_input
local owned = assert(lists.find_owned(require("quickfix_review.scope").id(review.scope())))
local saved
for _, item in ipairs(owned.items) do
	local note = annotations.get(item)
	if note and note.text == "DeltaView integration note" then
		saved = note
	end
end
assert(saved and saved.location.path == "README.md" and saved.location.line == 7)
print("quickfix_review DeltaView tests passed")
