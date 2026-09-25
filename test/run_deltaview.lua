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
	{
		old_path = "README.md",
		new_path = "README.md",
		hunks = {
			{
				lines = {
					{ formatted_diff_line_num = 0, line_type = "header" },
					{ formatted_diff_line_num = 3, line_type = "added", new_line_num = 7 },
					{
						formatted_diff_line_num = 5,
						line_type = "context",
						old_line_num = 8,
						new_line_num = 9,
					},
					{ formatted_diff_line_num = 7, line_type = "removed", old_line_num = 10 },
				},
			},
		},
	},
	{
		new_path = "second.lua",
		hunks = {
			{ lines = { { formatted_diff_line_num = 9, line_type = "added", new_line_num = 1 } } },
		},
	},
})
vim.api.nvim_set_current_buf(buf)

local function at(row)
	vim.api.nvim_win_set_cursor(0, { row, 0 })
	return resolver.location(buf)
end

local delta_resolver = resolver.detect(buf)
assert(delta_resolver.name == "deltaview")
local added = assert(at(4))
assert(added.path == "README.md" and added.line == 7 and added.side == "new")
local context = assert(at(6))
assert(context.path == "README.md" and context.line == 9 and context.side == "new")
local deleted = assert(at(8))
assert(deleted.path == "README.md" and deleted.line == 10 and deleted.side == "old")
local second_file = assert(at(10))
assert(second_file.path == "second.lua" and second_file.line == 1)
local function displayed_row(location)
	local rows = delta_resolver.display_lines(location, buf)
	assert(#rows == 1)
	return rows[1]
end
assert(displayed_row(added) == 4)
assert(displayed_row(context) == 6)
assert(displayed_row(deleted) == 8)
assert(displayed_row(second_file) == 10)
local unmappable, unmappable_err = at(1)
assert(not unmappable and unmappable_err:find("not on a mappable diff line", 1, true))

local ui = require("quickfix_review.ui")
local old_input = ui.note_input
local note_text
ui.note_input = function(_, callback)
	callback({ text = note_text })
end
note_text = "DeltaView old-side note"
vim.api.nvim_win_set_cursor(0, { 8, 0 })
review.add()
note_text = "DeltaView new-side note"
vim.api.nvim_win_set_cursor(0, { 4, 0 })
review.add()
ui.note_input = old_input
local owned = assert(lists.find_owned(require("quickfix_review.scope").id(review.scope())))
local saved = {}
for _, item in ipairs(owned.items) do
	local note = annotations.get(item)
	if note then
		saved[note.text] = note
	end
end
assert(
	saved["DeltaView old-side note"].location.path == "README.md"
		and saved["DeltaView old-side note"].location.line == 10
		and saved["DeltaView old-side note"].location.side == "old"
)
assert(
	saved["DeltaView new-side note"].location.path == "README.md"
		and saved["DeltaView new-side note"].location.line == 7
		and saved["DeltaView new-side note"].location.side == "new"
)
print("quickfix_review DeltaView tests passed")
