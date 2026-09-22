-- Hover redraw discipline: a pause on the note that is already displayed, or a
-- cursor move inside the same line, must not rebuild the floating window; leaving
-- the line is what closes it.
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
local file = root .. "/one.txt"
vim.fn.writefile({ "one", "two", "three", "four", "five" }, file)
vim.cmd.cd(root)
vim.cmd.edit(file)

local review = require("quickfix_review")
local marks = require("quickfix_review.marks")
local ui = require("quickfix_review.ui")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })
ui.note_input = function(_, callback) callback({ text = "hover note" }) end
vim.api.nvim_win_set_cursor(0, { 3, 0 })
review.add()

local function hover_float()
	local source = vim.api.nvim_get_current_win()
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if winid ~= source and vim.api.nvim_win_get_config(winid).relative ~= "" then return winid end
	end
end

marks.hover(0)
local first = assert(hover_float(), "hover must open on a note line")
local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(first), 0, -1, false), "\n")
assert(text:find("hover note", 1, true))

-- Stopping on the note that is already displayed redraws nothing.
marks.hover(0)
assert(hover_float() == first, "the displayed note must be reused, not recreated")

-- Moving inside the same line must not rebuild the float. This used to be closed by
-- the "CursorMoved" entry in the float's close_events, and reopened on the next pause.
vim.api.nvim_win_set_cursor(0, { 3, 2 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert(hover_float() == first, "moving inside the line must not rebuild the float")

-- Leaving the line is what closes it.
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert(not hover_float(), "leaving the note line must close the float")

-- Returning to the note may open it again.
vim.api.nvim_win_set_cursor(0, { 3, 0 })
marks.hover(0)
local again = assert(hover_float(), "returning to the note reopens the float")
assert(again ~= first)
print("quickfix_review hover redraw tests passed")
