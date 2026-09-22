-- The hover path must not shell out to git on every cursor move / hover: each call
-- fires ShellCmdPost, and every plugin reacting to it repaints on an otherwise idle
-- screen (a flickering cursor while notes are visible). `repo_root()` is on that path
-- (hover_payload -> resolver.location -> normal.resolve), so it is cached.
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
local file = root .. "/file.txt"
vim.fn.writefile({ "one", "two", "three", "four", "five" }, file)
vim.fn.system({ "git", "-C", root, "init", "-q" })
vim.cmd.cd(root)
vim.cmd.edit(file)

local review = require("quickfix_review")
local marks = require("quickfix_review.marks")
local location = require("quickfix_review.location")
local ui = require("quickfix_review.ui")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })
ui.note_input = function(_, callback)
	callback({ text = "note for the location test" })
end
vim.api.nvim_win_set_cursor(0, { 3, 0 })
review.add()

-- `clear_cache` is the API added with the cache; on older revisions there is nothing to
-- clear, and the first pass then shells out once per hover, which the assertions catch.
local clear_cache = location.clear_cache or function() end

local git_calls = 0
local system = vim.fn.system
vim.fn.system = function(cmd, ...)
	if type(cmd) == "table" and cmd[1] == "git" then
		git_calls = git_calls + 1
	end
	return system(cmd, ...)
end

local function pass()
	for _, lnum in ipairs({ 2, 3, 4 }) do
		vim.api.nvim_win_set_cursor(0, { lnum, 0 })
		marks.hover_follow()
		marks.hover(0)
	end
end

clear_cache()
pass()
local first = git_calls
pass()
local second = git_calls - first
local before_clear = git_calls
clear_cache()
location.repo_root(file)
local after_clear = git_calls - before_clear
vim.fn.system = system

assert(first == 1, "first pass should resolve the repo root exactly once, got " .. first)
assert(second == 0, "later cursor moves/hovers must not shell out, got " .. second)
assert(after_clear == 1, "clearing the cache must re-resolve, got " .. after_clear)
print("quickfix_review location cache tests passed")
