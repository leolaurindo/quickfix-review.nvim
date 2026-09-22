local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	vim.opt.rtp:prepend(vim.env[env] or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)

local review = require("quickfix_review")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local marks = require("quickfix_review.marks")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })

local owned, target = lists.ensure_owned({ title = "Quickfix Review" }, require("quickfix_review.scope").id(review.scope()))
for line, text in pairs({ [2] = "first note", [4] = "second note" }) do
	local item = { filename = vim.fs.joinpath(project, "README.md"), lnum = line, valid = 1, text = text, user_data = {} }
	local value = { root = project, path = "README.md", line = line, resolver = "normal" }
	if line == 4 then
		value.side, value.revision = "old", "historical"
	end
	assert(annotations.set(item, value, text))
	owned.items[#owned.items + 1] = item
end
assert(lists.replace(target, owned.items, 1, owned.changedtick))

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "editor:///" .. project:sub(2) .. "/README.md")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three", "four" })
vim.api.nvim_set_current_buf(buf)
marks.render(buf)

local source = vim.api.nvim_get_current_win()
local function floats()
	local out = {}
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if winid ~= source then
			out[#out + 1] = winid
		end
	end
	return out
end

local badge = assert(floats()[1])
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(badge), 0, -1, false), { "󰏫 2" }))
marks.refresh_rail(buf)
assert(floats()[1] == badge)
assert(marks.hover_all(buf))
local panel
for _, winid in ipairs(floats()) do
	if winid ~= badge then
		panel = winid
	end
end
assert(panel)
-- panel content is padded with one space per side, like the hover
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(panel), 0, -1, false), {
	" README.md:2", " first note", " ", " README.md:4 (old)", " second note",
}))
assert(not marks.hover_all(buf))
assert(#floats() == 1)
print("quickfix_review non-renderable rail tests passed")
